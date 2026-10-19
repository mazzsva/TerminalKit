import Foundation

extension TerminalSession {
    public struct Configuration: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        public var currentDirectoryURL: URL?
        public var usesShellIntegration: Bool

        public init(
            executableURL: URL,
            arguments: [String] = [],
            environment: [String: String] = TerminalSession.Configuration.terminalEnvironment(
                inheriting: ProcessInfo.processInfo.environment),
            currentDirectoryURL: URL? = nil,
            usesShellIntegration: Bool = false
        ) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
            self.currentDirectoryURL = currentDirectoryURL
            self.usesShellIntegration = usesShellIntegration
        }
    }
}

extension TerminalSession.Configuration {
    public static var loginShell: Self {
        loginShell(inheriting: ProcessInfo.processInfo.environment)
    }

    @usableFromInline
    static func terminalEnvironment(inheriting environment: [String: String]) -> [String: String] {
        var environment = environment
        for name in ["TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID"] {
            environment[name] = nil
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment
    }

    static func loginShell(inheriting environment: [String: String]) -> Self {
        Self(
            executableURL: shellURL,
            arguments: ["-l"],
            environment: terminalEnvironment(inheriting: environment),
            currentDirectoryURL: .homeDirectory,
            usesShellIntegration: true
        )
    }

    func integratingShell(scriptsIn directory: URL) -> Self {
        var configuration = self
        switch executableURL.lastPathComponent {
        case "zsh":
            configuration.environment["TERMINALKIT_ZSH_ZDOTDIR"] = environment["ZDOTDIR"]
            configuration.environment["ZDOTDIR"] = directory.appending(path: "zsh").path(percentEncoded: false)
        case "bash" where [[], ["-l"], ["--login"]].contains(arguments):
            configuration.arguments = [
                "--rcfile", directory.appending(path: "bash/terminalkit.bash").path(percentEncoded: false),
            ]
            configuration.environment["TERMINALKIT_BASH_INJECT"] = arguments.isEmpty ? "rc" : "login"
        default:
            break
        }
        return configuration
    }

    private static var shellURL: URL {
        guard let shell = getpwuid(getuid())?.pointee.pw_shell else {
            return URL(filePath: "/bin/zsh")
        }
        return URL(filePath: String(cString: shell))
    }
}
