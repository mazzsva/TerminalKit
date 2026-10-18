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

    @Test func runsTheProcess() async throws {
        let session = TerminalSession(configuration: shell("exit"))
        try session.start()
        #expect(session.state == .running)
        await waitForExit(of: session)
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

    @Test func sendsInputToTheProcess() async throws {
        let session = TerminalSession(configuration: shell("read line; echo \"got $line\""))
        try session.start()
        session.send(Array("hello\r".utf8))
        await waitForExit(of: session)
        #expect(text(of: session).contains("got hello"))
    }

    @Test func answersTheQueriesOfTheProcess() async throws {
        let session = TerminalSession(
            configuration: shell("stty raw -echo; printf '\\033[6n'; head -c 6 | od -An -tx1")
        )
        try session.start()
        await waitForExit(of: session)
        #expect(text(of: session).contains("1b  5b  31  3b  31  52"))
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
            configuration: shell("trap 'stty size; exit' WINCH; echo ready; while :; do sleep 0.1; done")
        )
        try session.start()
        await waitForText("ready", in: session)
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
private func waitForExit(
    of session: TerminalSession,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> TerminalSession.State? {
    for await state in Observations({ session.state }) where state != .running {
        return state
    }
    Issue.record("The process did not exit. Screen: \(text(of: session))", sourceLocation: sourceLocation)
    return nil
}

@MainActor
private func waitForText(
    _ line: String,
    in session: TerminalSession,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for await text in Observations({ text(of: session) }) where text.contains(line) {
        return
    }
    Issue.record("The screen did not show \"\(line)\". Screen: \(text(of: session))", sourceLocation: sourceLocation)
}

@MainActor
private func text(of session: TerminalSession) -> [String] {
    session.terminal.screen.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
}
