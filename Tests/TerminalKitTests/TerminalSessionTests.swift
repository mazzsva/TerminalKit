import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
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

    @Test func startsIdle() {
        #expect(TerminalSession(configuration: shell("exit")).state == .idle)
    }

    @Test func runsTheProcess() throws {
        let session = TerminalSession(configuration: shell("sleep 1"))
        try session.start()
        #expect(session.state == .running)
    }

    @Test func showsTheOutputOfTheProcess() async throws {
        let session = TerminalSession(configuration: shell("printf 'hello\\nworld'"))
        try session.start()
        await waitForExit(of: session)
        let lines = session.terminal.screen.prefix(2)
            .map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
        #expect(lines == ["hello", "world"])
    }

    @Test func reportsTheExitOfTheProcess() async throws {
        let session = TerminalSession(configuration: shell("exit 3"))
        try session.start()
        #expect(await waitForExit(of: session) == .exited(.exit(3)))
    }

    @Test func showsTheTitleOfTheProcess() async throws {
        let session = TerminalSession(configuration: shell("printf '\\033]0;Title\\007'"))
        try session.start()
        await waitForExit(of: session)
        #expect(session.title == "Title")
    }

    @Test func startsTheProcessWithTheSizeOfTheScreen() async throws {
        let session = TerminalSession(configuration: shell("stty size"))
        session.resize(columns: 100, rows: 30)
        try session.start()
        await waitForExit(of: session)
        #expect(text(of: session).first == "30 100")
    }

    @Test func resizesTheProcess() async throws {
        let session = TerminalSession(
            configuration: shell("trap 'stty size; exit' WINCH; echo ready; while :; do sleep 0.01; done")
        )
        try session.start()
        for await text in Observations({ text(of: session) }) where text.contains("ready") {
            break
        }
        session.resize(columns: 100, rows: 30)
        await waitForExit(of: session)
        #expect(text(of: session).contains("30 100"))
    }

    @Test func throwsWhenTheProcessCannotStart() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/missing")))
        #expect(throws: POSIXError(.ENOENT)) {
            try session.start()
        }
        #expect(session.state == .idle)
    }
}

private func shell(_ script: String) -> TerminalSession.Configuration {
    TerminalSession.Configuration(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: [:])
}

@MainActor
@discardableResult
private func waitForExit(of session: TerminalSession) async -> TerminalSession.State? {
    for await state in Observations({ session.state }) where state != .running {
        return state
    }
    return nil
}

@MainActor
private func text(of session: TerminalSession) -> [String] {
    session.terminal.screen.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
}
