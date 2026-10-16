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
