import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSessionTests {
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
        #expect(TerminalSession(running: "exit").state == .idle)
    }

    @Test func runsTheProcess() async throws {
        let session = TerminalSession(running: "exit")
        try session.start()
        #expect(session.state == .running)
        await session.waitForExit()
    }

    @Test func showsTheOutputOfTheProcess() async throws {
        let session = TerminalSession(running: "printf 'hello\\nworld'")
        try session.start()
        await session.waitForExit()
        #expect(session.lines.prefix(2) == ["hello", "world"])
    }

    @Test func reportsTheExitOfTheProcess() async throws {
        let session = TerminalSession(running: "exit 3")
        try session.start()
        await session.waitForExit()
        #expect(session.state == .exited)
    }

    @Test func sendsInputToTheProcess() async throws {
        let session = TerminalSession(running: "read line; echo \"got $line\"")
        try session.start()
        session.send(Array("hello\r".utf8))
        await session.waitForExit()
        #expect(session.lines.contains("got hello"))
    }

    @Test func answersTheQueriesOfTheProcess() async throws {
        let session = TerminalSession(running: "stty raw -echo; printf '\\033[6n'; head -c 6 | od -An -tx1")
        try session.start()
        await session.waitForExit()
        #expect(session.lines.contains("1b  5b  31  3b  31  52"))
    }

    @Test func startsTheProcessWithTheSizeOfTheScreen() async throws {
        let session = TerminalSession(running: "stty size")
        session.resize(columns: 100, rows: 30)
        try session.start()
        await session.waitForExit()
        #expect(session.lines.first == "30 100")
    }

    @Test func resizesTheProcess() async throws {
        let session = TerminalSession(running: "trap 'stty size; exit' WINCH; echo ready; while :; do sleep 0.1; done")
        try session.start()
        await session.waitForText("ready")
        session.resize(columns: 100, rows: 30)
        await session.waitForExit()
        #expect(session.lines.contains("30 100"))
    }

    @Test func throwsWhenTheProcessCannotStart() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/missing")))
        #expect(throws: POSIXError(.ENOENT)) {
            try session.start()
        }
        #expect(session.state == .idle)
    }
}
