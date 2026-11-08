import Foundation

extension TerminalSession {
    public struct Configuration: Sendable {
        public var executableURL: URL {
            didSet {
                isLoginShell = false
            }
        }
        public var arguments: [String] {
            didSet {
                isLoginShell = false
            }
        }
        public var environment: [String: String]
        public var currentDirectoryURL: URL? {
            didSet {
                guard isLoginShell else {
                    return
                }
                arguments = Self.loginArguments(in: currentDirectoryURL)
                isLoginShell = true
            }
        }
        var isLoginShell = false

        public init(
            executableURL: URL,
            arguments: [String] = [],
            environment: [String: String] = TerminalSession.Configuration.terminalEnvironment(
                inheriting: ProcessInfo.processInfo.environment),
            currentDirectoryURL: URL? = nil
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.currentDirectoryURL = currentDirectoryURL
        }
    }
}

extension TerminalSession.Configuration {
    public static var loginShell: Self {
        var configuration = loginShell(inheriting: ProcessInfo.processInfo.environment)
        configuration.isLoginShell = true
        return configuration
    }

    public static func loginShell(running command: [String]) -> Self {
        loginShell(running: command, shellURL: shellURL)
    }

    static func loginShell(running command: [String], shellURL: URL) -> Self {
        var configuration = loginShell(inheriting: ProcessInfo.processInfo.environment)
        configuration.arguments =
            ["-pfql", userName, shellURL.path(percentEncoded: false)]
            + shellArguments(running: command, shellURL: shellURL)
        configuration.currentDirectoryURL = .homeDirectory
        return configuration
    }

    static func shellArguments(running command: [String], shellURL: URL) -> [String] {
        let fish = shellURL.lastPathComponent == "fish"
        let words = command.map {
            quoted(fish ? $0.replacingOccurrences(of: "\\", with: "\\\\", options: .literal) : $0)
        }
        return ["-l", "-i", "-c", "exec -- " + words.joined(separator: " ")]
    }

    static func loginArguments(in directory: URL?, shellURL: URL = shellURL) -> [String] {
        guard directory != nil else {
            return ["-pf", userName]
        }
        let path = shellURL.path(percentEncoded: false)
        let words = [shellURL.lastPathComponent, path]
            .map { word in
                word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-".contains($0)) }
                    ? word : quoted(word)
            }
        return ["-pfl", userName, "/bin/bash", "-c", "exec -la " + words.joined(separator: " ")]
    }

    private static func quoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''", options: .literal) + "'"
    }

    @usableFromInline
    static func terminalEnvironment(
        inheriting environment: [String: String],
        locale: Locale = Locale(
            languageCode: Locale.preferredLocales.first?.language.languageCode,
            languageRegion: Locale.current.region)
    ) -> [String: String] {
        var environment = environment
        for name in [
            "TERM_SESSION_ID", "TMUX", "TMUX_PANE", "STY", "LC_TERMINAL",
            "LC_TERMINAL_VERSION", "ITERM_SESSION_ID", "ITERM_PROFILE", "KITTY_WINDOW_ID", "KITTY_PID", "COLORFGBG",
            "COLUMNS", "LINES", "TERMINFO", "CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CURSOR_TRACE_ID",
            "TERMINAL_EMULATOR", "ALACRITTY_LOG", "ALACRITTY_WINDOW_ID", "WEZTERM_PANE", "WT_SESSION", "VTE_VERSION",
            "KONSOLE_VERSION", "GNOME_TERMINAL_SERVICE", "XTERM_VERSION", "TERMINATOR_UUID", "TILIX_ID", "ZED_TERM",
            "ZELLIJ", "CLAUDE_CODE_SSE_PORT", "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY",
        ] {
            environment[name] = nil
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Apple_Terminal"
        environment["TERM_PROGRAM_VERSION"] = "488"
        if environment["LANG"] == nil {
            let name = locale.identifier + ".UTF-8"
            environment["LANG"] =
                FileManager.default.fileExists(atPath: "/usr/share/locale/" + name) ? name : "en_US.UTF-8"
        }
        return environment
    }

    static func loginShell(inheriting environment: [String: String]) -> Self {
        Self(
            executableURL: URL(filePath: "/usr/bin/login"),
            arguments: loginArguments(in: nil),
            environment: terminalEnvironment(inheriting: environment)
        )
    }

    static var userName: String {
        guard let name = getpwuid(getuid())?.pointee.pw_name else {
            return NSUserName()
        }
        return String(cString: name)
    }

    private static var shellURL: URL {
        guard let shell = getpwuid(getuid())?.pointee.pw_shell else {
            return URL(filePath: "/bin/zsh")
        }
        return URL(filePath: String(cString: shell))
    }
}
