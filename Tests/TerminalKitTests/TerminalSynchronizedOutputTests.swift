import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSynchronizedOutputTests {
    @Test func drawsTheScreenOfTheStartUntilTheEnd() async throws {
        let session = TerminalSession(
            running: "stty -echo; printf 'a\\033[?2026h'; read x; printf b; read y; printf '\\033[?2026l'; read z"
        )
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        await session.waitForLiveText { $0.hasPrefix("a") && session.liveTerminal.isSynchronizingOutput }
        let start = try image(of: view)

        session.send(Array("\r".utf8))
        await session.waitForLiveText { $0.hasPrefix("ab") }
        #expect(try image(of: view) == start)
        #expect(session.lines.first == "a")

        session.send(Array("\r".utf8))
        await session.waitForText("ab")
        #expect(try image(of: view) != start)
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func showsTheScreenAfterTheTimeout() async throws {
        let session = TerminalSession(running: "stty -echo; printf 'a\\033[?2026hb'; read x")
        session.synchronizedOutputTimeout = .milliseconds(200)
        try session.start()
        await session.waitForLiveText { $0.hasPrefix("ab") }
        let start = ContinuousClock.now
        #expect(session.lines.first == "a")

        await session.waitForText("ab")
        #expect(ContinuousClock.now - start > .milliseconds(100))
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func showsTheScreenAfterTheTimeoutWhileOutputContinues() async throws {
        let session = TerminalSession(
            running: "printf '\\033[?2026h'; while :; do printf x; sleep 0.02; done"
        )
        session.synchronizedOutputTimeout = .milliseconds(200)
        try session.start()
        await session.waitForText("x")
        #expect(session.liveTerminal.isSynchronizingOutput == false)
    }

    @Test func startsTheTimeoutAgainForEachUpdate() async throws {
        let session = TerminalSession(
            running: "stty -echo; printf '\\033[?2026h'; sleep 0.6; printf '\\033[?2026l\\033[?2026hb'; read x"
        )
        try session.start()
        await session.waitForLiveText { $0.hasPrefix("b") }
        try await Task.sleep(for: .milliseconds(600))
        #expect(session.lines.first == "")

        await session.waitForText("b")
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func showsTheScreenWhenTheViewResizes() async throws {
        let session = TerminalSession(running: "stty -echo; printf 'a\\033[?2026hb'; read x")
        session.synchronizedOutputTimeout = .seconds(60)
        try session.start()
        await session.waitForLiveText { $0.hasPrefix("ab") }
        #expect(session.lines.first == "a")

        TerminalContentView(session: session).fit(to: CGSize(width: 300, height: 200))
        #expect(session.lines.first == "ab")
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func showsTheScreenWhenTheProcessExits() async throws {
        let session = TerminalSession(running: "printf 'a\\033[?2026hb'")
        session.synchronizedOutputTimeout = .seconds(60)
        try session.start()
        await session.waitForExit()
        #expect(session.lines.first == "ab")
    }
}

extension TerminalSession {
    fileprivate func waitForLiveText(_ isComplete: @escaping (String) -> Bool) async {
        for await text in Observations({ String(self.liveTerminal.screen[0].map(\.character)) }) where isComplete(text)
        {
            return
        }
    }
}

@MainActor
private func image(of view: NSView) throws -> Data {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return try #require(representation.tiffRepresentation)
}
