import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalBellTests {
    @Test func ringsTheBellOnceForABurst() async throws {
        let session = TerminalSession(running: "read line; printf 'a\\a\\a\\a'")
        let view = TerminalContentView(session: session)
        let bell = Bell(view)
        let window = NSWindow(contentView: view)
        try session.start()
        try await Task.sleep(for: .milliseconds(100))
        session.send(Array("\r".utf8))
        await session.waitForExit()
        while bell.rings == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(bell.rings == 1)
        #expect(session.bellCount == 3)
        #expect(window.contentView === view)
    }

    @Test func ringsTheBellAtMostTwiceASecond() async throws {
        let session = TerminalSession(running: "read line; printf '\\a'; sleep 0.05; printf '\\a'")
        let view = TerminalContentView(session: session)
        let bell = Bell(view)
        let window = NSWindow(contentView: view)
        try session.start()
        try await Task.sleep(for: .milliseconds(100))
        session.send(Array("\r".utf8))
        await session.waitForExit()
        try await Task.sleep(for: .milliseconds(200))
        #expect(bell.rings == 1)
        #expect(session.bellCount == 2)
        #expect(window.contentView === view)
    }

    @Test func ringsNoBellOutsideAWindow() async throws {
        let session = TerminalSession(running: "printf '\\a'")
        let bell = Bell(TerminalContentView(session: session))
        try session.start()
        await session.waitForExit()
        try await Task.sleep(for: .milliseconds(200))
        #expect(bell.rings == 0)
        #expect(session.bellCount == 1)
    }

    @Test func ringsNoBellForAnEarlierBell() async throws {
        let session = TerminalSession(running: "printf '\\a'")
        try session.start()
        await session.waitForExit()
        let view = TerminalContentView(session: session)
        let bell = Bell(view)
        let window = NSWindow(contentView: view)
        try await Task.sleep(for: .milliseconds(200))
        #expect(bell.rings == 0)
        #expect(window.contentView === view)
    }

    @Test func ringsNoBellAfterTheViewLeavesTheWindow() async throws {
        let session = TerminalSession(running: "read line; printf '\\a'")
        let view = TerminalContentView(session: session)
        let bell = Bell(view)
        let window = NSWindow(contentView: view)
        window.contentView = NSView()
        try session.start()
        session.send(Array("\r".utf8))
        await session.waitForExit()
        try await Task.sleep(for: .milliseconds(200))
        #expect(bell.rings == 0)
    }

    @Test func releasesTheSessionWithTheWindow() async throws {
        weak var weakSession: TerminalSession?
        weak var weakView: TerminalContentView?
        do {
            let session = TerminalSession(running: "read line")
            let view = TerminalContentView(session: session)
            weakSession = session
            weakView = view
            try session.start()
            _ = NSWindow(contentView: view)
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(weakView == nil)
        #expect(weakSession == nil)
    }

    @Test(arguments: [(nil, true), (0.0, false), (0.49, false), (0.5, true), (5.0, true), (-1.0, false)])
    func throttlesTheBell(secondsSinceLastBell: Double?, rings: Bool) {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let lastBellDate = secondsSinceLastBell.map { date.addingTimeInterval(-$0) }
        #expect(TerminalContentView.ringsBell(at: date, lastBellDate: lastBellDate) == rings)
    }
}

@MainActor
private final class Bell {
    var rings = 0

    init(_ view: TerminalContentView) {
        view.ringBell = { [unowned self] in
            rings += 1
        }
    }
}
