import Foundation

extension TerminalSession {
    public struct Configuration: Equatable, Sendable {
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
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
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
