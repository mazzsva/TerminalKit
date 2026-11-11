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

    @Test func drawsOnlyCompleteFramesOfAFullScreenRedraw() async throws {
        let session = TerminalSession(
            running: """
                stty raw -echo; exec /usr/bin/perl -e '$| = 1; my $n = 0; do { my $c = chr(97 + $n++); \
                my $f = "\\e[?2026h\\e[H" . join("\\r\\n", ($c x 200) x 60) . "\\e[?2026l"; my $s = int(length($f) / 4) + 1; \
                for my $i (0 .. 3) { syswrite(STDOUT, substr($f, $i * $s, $s)); select(undef, undef, undef, 0.02) } \
                } while (sysread(STDIN, my $k, 1))'
                """
        )
        session.synchronizedOutputClock = ManualClock()
        session.resize(columns: 200, rows: 60)
        var frames: [Set<String>] = []
        var updateCount = 0
        session.terminalDidChange = {
            let terminal = session.terminal
            frames.append(Set(terminal.screen.joined().map(terminal.character(of:))))
            if session.liveTerminal.isSynchronizingOutput {
                updateCount += 1
            }
        }
        try session.start()
        let characters = (0 ... 10).map { String(UnicodeScalar(UInt8(97 + $0))) }
        for character in characters {
            let line = String(repeating: character, count: 200)
            for await lines in Observations({ session.lines }) where lines.allSatisfy({ $0 == line }) {
                break
            }
            if character != characters.last {
                session.send("x")
            }
        }
        session.terminalDidChange = nil
        session.terminate()
        await session.waitForExit()
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
