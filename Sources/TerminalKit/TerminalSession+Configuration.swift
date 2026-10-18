import Foundation

extension TerminalSession {
    public struct Configuration: Sendable {
        public var executableURL: URL
        public var arguments: [String]
        public var environment: [String: String]
        public var currentDirectoryURL: URL?

        public init(
            executableURL: URL,
            arguments: [String] = [],
            environment: [String: String] = ProcessInfo.processInfo.environment,
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
        loginShell(inheriting: ProcessInfo.processInfo.environment)
    }

    static func loginShell(inheriting environment: [String: String]) -> Self {
        var environment = environment
        for name in ["TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID"] {
            environment[name] = nil
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return Self(
            executableURL: shellURL,
            arguments: ["-l"],
            environment: environment,
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
