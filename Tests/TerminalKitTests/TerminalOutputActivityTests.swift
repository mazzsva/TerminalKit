import Foundation
import TerminalCore
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalOutputActivityTests {
    private let fullChunk = [UInt8](repeating: UInt8(ascii: "a"), count: PseudoTerminal.Output.capacity)

    @Test func keepsTheActivityUntilOneSecondAfterTheLastFullChunk() async throws {
        let session = TerminalSession()
        let clock = ManualClock()
        session.outputActivityClock = clock
        session.receive(fullChunk)
        let activity = try #require(session.outputActivity)

        try await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(600))
        session.receive(fullChunk)
        try await clock.waitForSleepers(2)
        clock.advance(by: .milliseconds(600))
        await yieldToTheTimer()
        #expect(session.outputActivity === activity)

        clock.advance(by: .milliseconds(400))
        while session.outputActivity != nil {
            await Task.yield()
        }
    }

    @Test func endsTheActivityWhenTheSessionEnds() async throws {
        let session = TerminalSession(running: "stty -echo; read x")
        session.outputActivityClock = ManualClock()
        try session.start()
        session.receive(fullChunk)
        #expect(session.outputActivity != nil)

        session.send(Array("\r".utf8))
        await session.waitForExit()
        #expect(session.outputActivity == nil)
    }

    @Test func beginsNoActivityForASmallChunk() {
        let session = TerminalSession()
        session.receive(Array(fullChunk.dropLast()))
        #expect(session.outputActivity == nil)
    }
}

private func yieldToTheTimer() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}
