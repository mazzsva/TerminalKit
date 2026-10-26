import Foundation
import Synchronization
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
        let environment = TerminalSession.Configuration.loginShell(inheriting: ["TERM": "dumb", "PATH": "/bin"])
            .environment
        #expect(
            environment == ["TERM": "xterm-256color", "COLORTERM": "truecolor", "LANG": "en_US.UTF-8", "PATH": "/bin"])
    }

    @Test func describesTheTerminalToAnyProcess() {
        let environment = TerminalSession.Configuration(executableURL: URL(filePath: "/bin/sh")).environment
        let inherited = ProcessInfo.processInfo.environment
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["COLORTERM"] == "truecolor")
        #expect(environment["LANG"] == inherited["LANG"] ?? "en_US.UTF-8")
        #expect(environment["PATH"] == inherited["PATH"])
        #expect(environment["TERM_PROGRAM"] == nil)
        #expect(environment["TERM_SESSION_ID"] == nil)
    }

    @Test func keepsTheLanguageOfTheUser() {
        let environment = TerminalSession.Configuration.loginShell(inheriting: ["LANG": "pt_BR.UTF-8"]).environment
        #expect(environment["LANG"] == "pt_BR.UTF-8")
    }

    @Test func removesTheIdentityOfTheParentTerminal() {
        let environment = TerminalSession.Configuration
            .loginShell(
                inheriting: ["TERM_PROGRAM": "Apple_Terminal", "TERM_PROGRAM_VERSION": "470", "TERM_SESSION_ID": "1"]
            )
            .environment
        #expect(environment["TERM_PROGRAM"] == nil)
        #expect(environment["TERM_PROGRAM_VERSION"] == nil)
        #expect(environment["TERM_SESSION_ID"] == nil)
    }

    @Test func runsTheCommandInTheInteractiveLoginShell() {
        let configuration = TerminalSession.Configuration.loginShell(running: ["claude", "--resume", "it's"])
        let loginShell = TerminalSession.Configuration.loginShell
        #expect(configuration.executableURL == loginShell.executableURL)
        #expect(configuration.arguments == ["-l", "-i", "-c", "exec -- 'claude' '--resume' 'it'\\''s'"])
        #expect(configuration.environment == loginShell.environment)
        #expect(configuration.currentDirectoryURL == loginShell.currentDirectoryURL)
        #expect(loginShell.isLoginShell)
        #expect(!configuration.isLoginShell)
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
        #expect(session.state == .exited(.exit(3)))
    }

    @Test func countsTheBellsOfTheProcess() async throws {
        let session = TerminalSession(running: "printf 'a\\a\\033]0;t\\007\\a'")
        try session.start()
        await session.waitForExit()
        #expect(session.bellCount == 2)
    }

    @Test func showsTheTitleOfTheProcess() async throws {
        let session = TerminalSession(running: "printf '\\033]0;Title\\007'")
        try session.start()
        await session.waitForExit()
        #expect(session.title == "Title")
    }

    @Test func showsTheCurrentDirectoryOfTheProcess() async throws {
        let session = TerminalSession(running: "printf '\\033]7;file:///tmp/a%%20b\\007'")
        try session.start()
        await session.waitForExit()
        #expect(session.currentDirectory == URL(filePath: "/tmp/a b"))
    }

    @Test func keepsTheTitleForOtherOutput() async throws {
        let session = TerminalSession(running: "printf '\\033]0;Title\\007'; read line; echo more")
        try session.start()
        for await title in Observations({ session.title }) where title == "Title" {
            break
        }
        let changes = Mutex(0)
        withObservationTracking {
            _ = session.title
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        session.send(Array("\r".utf8))
        await session.waitForExit()
        #expect(session.lines.contains("more"))
        #expect(changes.withLock { $0 } == 0)
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

    @Test func passesEachWordOfTheCommandUnchanged() async throws {
        let words = [
            "a b", "it's", "\"q\"", "$HOME", "*", "", "back\\slash", "!x", "~", "café €",
            "x'\u{301}$(/bin/echo injected)'\u{301}",
        ]
        let session = try await runInZsh(["/bin/sh", "-c", "printf '<%s>\\n' \"$@\"", "sh"] + words)
        #expect(session.lines.prefix(words.count) == ArraySlice(words.map { "<\($0)>" }))
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func findsTheCommandOnThePathOfTheShellStartupFiles() async throws {
        let session = try await runInZsh(["tool"], startup: "export PATH=\"$HOME/bin dir:$PATH\"")
        #expect(session.lines.first == "found")
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func runsTheCommandInTheCurrentDirectory() async throws {
        let session = try await runInZsh(["./tool"])
        #expect(session.lines.first == "found")
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func reportsTheExitStatusOfTheCommand() async throws {
        let session = try await runInZsh(["/bin/sh", "-c", "exit 7"], startup: "trap 'exit 1' EXIT")
        #expect(session.state == .exited(.exit(7)))
    }

    @Test func reportsTheSignalOfTheCommand() async throws {
        let session = try await runInZsh(["/bin/sh", "-c", "kill -TERM $$"], startup: "trap 'exit 1' EXIT")
        #expect(session.state == .exited(.uncaughtSignal(SIGTERM)))
    }

    @Test func runsAFirstWordThatStartsWithAHyphenAsTheCommand() async throws {
        let session = try await runInZsh(["-a", "name", "/bin/sh", "-c", "exit 7"])
        #expect(session.state == .exited(.exit(127)))
    }

    @Test func failsWhenTheCommandIsEmpty() async throws {
        let session = try await runInZsh([], startup: "trap 'exit 4' EXIT")
        #expect(session.state == .exited(.exit(1)))
    }

    @Test func throwsWhenTheProcessCannotStart() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/missing")))
        #expect(throws: POSIXError(.ENOENT)) {
            try session.start()
        }
        #expect(session.state == .idle)
    }
}

@MainActor
private func runInZsh(_ command: [String], startup: String = "") async throws -> TerminalSession {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let tool = home.appending(path: "bin dir/tool")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\necho found\n".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))
    try Data(startup.utf8).write(to: home.appending(path: ".zshrc"))
    var configuration = TerminalSession.Configuration.loginShell(running: command)
    configuration.executableURL = URL(filePath: "/bin/zsh")
    configuration.environment = TerminalSession.Configuration.terminalEnvironment(
        inheriting: ["HOME": home.path(percentEncoded: false), "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin"])
    configuration.currentDirectoryURL = tool.deletingLastPathComponent()
    let session = TerminalSession(configuration: configuration)
    try session.start()
    await session.waitForExit()
    return session
}
