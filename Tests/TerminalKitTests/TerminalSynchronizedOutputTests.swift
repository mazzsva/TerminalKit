import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(3)))
struct TerminalSynchronizedOutputTests {
    @Test func drawsTheScreenOfTheStartUntilTheEnd() async throws {
        let session = TerminalSession(
            running: "stty -echo; printf 'a\\033[?2026h'; read x; printf b; read y; printf '\\033[?2026l'; read z"
        )
        session.synchronizedOutputClock = ManualClock()
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

    @Test func drawsOnlyCompleteFramesOfAFullScreenRedraw() {
        let session = TerminalSession(running: "exit")
        session.synchronizedOutputClock = ManualClock()
        session.resize(columns: 200, rows: 60)
        var frames: [Set<String>] = []
        var updateCount = 0
        let characters = (0 ... 10).map { String(UnicodeScalar(UInt8(97 + $0))) }
        for character in characters {
            let screen = Array(repeating: String(repeating: character, count: 200), count: 60).joined(separator: "\r\n")
            let frame = Array("\u{1B}[?2026h\u{1B}[H\(screen)\u{1B}[?2026l".utf8)
            for start in stride(from: 0, to: frame.count, by: 1_024) {
                session.receive(Array(frame[start ..< min(start + 1_024, frame.count)]))
                let terminal = session.terminal
                frames.append(Set(terminal.screen.joined().map(terminal.character(of:))))
                if session.liveTerminal.isSynchronizingOutput {
                    updateCount += 1
                }
            }
        }
        #expect(updateCount > 0)
        #expect(frames.allSatisfy { $0.count == 1 })
        #expect(
            frames.compactMap(\.first).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
                .drop { $0 == " " } == characters[...])
    }

    @Test func showsTheScreenAfterTheTimeout() async throws {
        let session = TerminalSession(running: "stty -echo; printf 'a\\033[?2026hb'; read x")
        let clock = ManualClock()
        session.synchronizedOutputClock = clock
        try session.start()
        await session.waitForLiveText { $0.hasPrefix("ab") }
        try await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(999))
        await yieldToTheTimer()
        #expect(session.lines.first == "a")

        clock.advance(by: .milliseconds(1))
        await session.waitForText("ab")
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func showsTheScreenAfterTheTimeoutWhileOutputContinues() async throws {
        let session = TerminalSession(
            running: "printf '\\033[?2026h'; while :; do printf x; sleep 0.02; done"
        )
        let clock = ManualClock()
        session.synchronizedOutputClock = clock
        try session.start()
        try await clock.waitForSleepers(1)
        clock.advance(by: .seconds(1))
        await session.waitForText("x")
        #expect(session.liveTerminal.isSynchronizingOutput == false)
        session.terminate()
        await session.waitForExit()
    }

    @Test func startsTheTimeoutAgainForEachUpdate() async throws {
        let session = TerminalSession(
            running: "stty -echo; printf '\\033[?2026h'; read x; printf '\\033[?2026l\\033[?2026hb'; read y"
        )
        let clock = ManualClock()
        session.synchronizedOutputClock = clock
        try session.start()
        for await isSynchronizing in Observations({ session.liveTerminal.isSynchronizingOutput }) where isSynchronizing
        {
            break
        }
        try await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(600))
        session.send(Array("\r".utf8))
        await session.waitForLiveText { $0.hasPrefix("b") }
        try await clock.waitForSleepers(2)
        clock.advance(by: .milliseconds(600))
        await yieldToTheTimer()
        #expect(session.lines.first == "")

        clock.advance(by: .milliseconds(400))
        await session.waitForText("b")
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func showsTheScreenWhenTheViewResizes() async throws {
        let session = TerminalSession(running: "stty -echo; printf 'a\\033[?2026hb'; read x")
        session.synchronizedOutputClock = ManualClock()
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
        session.synchronizedOutputClock = ManualClock()
        try session.start()
        await session.waitForExit()
        #expect(session.lines.first == "ab")
    }
}

extension TerminalSession {
    fileprivate func waitForLiveText(_ isComplete: @escaping (String) -> Bool) async {
        for await text in Observations({ self.liveTerminal.screen[0].map(self.liveTerminal.character(of:)).joined() })
        where isComplete(text) {
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

@MainActor
private func yieldToTheTimer() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}
