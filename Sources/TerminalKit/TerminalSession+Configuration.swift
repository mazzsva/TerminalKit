import Foundation

extension TerminalSession {
    public struct Configuration: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        public var currentDirectoryURL: URL?
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
        var configuration = loginShell(inheriting: ProcessInfo.processInfo.environment)
        let words = command.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''", options: .literal) + "'" }
        configuration.arguments += ["-i", "-c", "exec -- " + words.joined(separator: " ")]
        return configuration
    }

    @usableFromInline
    static func terminalEnvironment(inheriting environment: [String: String]) -> [String: String] {
        var environment = environment
        for name in [
            "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "TMUX", "TMUX_PANE", "STY", "LC_TERMINAL",
            "LC_TERMINAL_VERSION", "ITERM_SESSION_ID", "ITERM_PROFILE", "KITTY_WINDOW_ID", "KITTY_PID", "COLORFGBG",
            "COLUMNS", "LINES", "TERMINFO", "CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION",
        ] {
            environment[name] = nil
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        if environment["CLAUDE_CODE_FORCE_STRIKETHROUGH"] == nil {
            environment["CLAUDE_CODE_FORCE_STRIKETHROUGH"] = "1"
        }
        return environment
    }

    static func loginShell(inheriting environment: [String: String]) -> Self {
        Self(
            executableURL: shellURL,
            arguments: ["-l"],
            environment: terminalEnvironment(inheriting: environment),
            currentDirectoryURL: .homeDirectory
        )
    }

    private static var shellURL: URL {
        guard let shell = getpwuid(getuid())?.pointee.pw_shell else {
            return URL(filePath: "/bin/zsh")
        }
        return URL(filePath: String(cString: shell))
    }
}
