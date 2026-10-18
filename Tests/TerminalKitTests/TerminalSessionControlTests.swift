import Darwin
import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSessionControlTests {
    @Test func terminatesTheProcessAndItsChildren() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let session = TerminalSession(
            running: "/bin/sleep 33 & echo $! > '\(file.path(percentEncoded: false))'; echo ready; wait")
        try session.start()
        await session.waitForText("ready")
        let childIdentifier = try #require(
            pid_t(String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .newlines)))
        session.terminate()
        await session.waitForExit()
        #expect(session.state == .exited(.uncaughtSignal(SIGHUP)))
        while kill(childIdentifier, 0) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func terminatesAnInteractiveShell() async throws {
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/zsh"),
                arguments: ["-f", "-i"],
                environment: ["HOME": "/nonexistent", "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin"]
            )
        )
        try session.start()
        session.send("echo ready\r")
        await session.waitForText("ready")
        session.terminate()
        await session.waitForExit()
        #expect(session.state != .running)
    }

    @Test func terminatesNothingBeforeTheStartOrAfterTheExit() async throws {
        let session = TerminalSession(running: "exit 4")
        session.terminate()
        #expect(session.state == .idle)
        try session.start()
        await session.waitForExit()
        session.terminate()
        #expect(session.state == .exited(.exit(4)))
    }

    @Test func sendsText() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=4 2>/dev/null | od -An -tx1")
        try session.start()
        await session.waitForText("ready")
        session.send("é€")
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("c3  a9  e2  82") })
    }

    @Test func pastesInTheModeOfTheLiveTerminal() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[?2026h\\033[?2004hready'; dd bs=1 count=15 2>/dev/null | od -An -c"
        )
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesBracketedPaste }) where isEnabled {
            break
        }
        #expect(!session.terminal.usesBracketedPaste)
        session.paste("a\nb\u{1B}")
        let output = await session.linesAfterExit().joined(separator: " ")
        #expect(output.contains("033   [   2   0   0   ~   a  \\r   b 033   [   2   0   1   ~"))
    }

    @Test func pastesWithoutBrackets() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=5 2>/dev/null | od -An -c")
        try session.start()
        await session.waitForText("ready")
        session.paste("a\r\nb\nc")
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("a  \\r   b  \\r   c") })
    }
}
