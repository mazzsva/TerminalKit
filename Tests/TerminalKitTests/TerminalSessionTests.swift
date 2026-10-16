import Foundation
import TerminalKit
import Testing

@MainActor
struct TerminalSessionTests {
    @Test func keepsTheConfiguration() {
        let configuration = TerminalSession.Configuration(
            executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "exit"])
        let session = TerminalSession(configuration: configuration)
        #expect(session.configuration == configuration)
    }
}
