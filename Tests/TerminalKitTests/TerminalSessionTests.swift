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

    @Test func startsTheLoginShellInTheHomeDirectory() {
        let configuration = TerminalSession.Configuration.loginShell
        #expect(configuration.executableURL.path(percentEncoded: false).hasPrefix("/"))
        #expect(configuration.arguments == ["-l"])
        #expect(configuration.currentDirectoryURL == .homeDirectory)
    }

    @Test func describesTheTerminalToTheLoginShell() {
        let environment = TerminalSession.Configuration.loginShell.environment
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["LANG"] != nil)
    }
}
