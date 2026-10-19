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
        view.currentDate = { Date(timeIntervalSince1970: 0) }
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

    @Test func ringsTheBellInOneViewOfTheSession() async throws {
        let session = TerminalSession(running: "read line; printf '\\a'; read line")
        let views = [TerminalContentView(session: session), TerminalContentView(session: session)]
        let bells = views.map(Bell.init)
        let windows = views.map { view in
            view.currentDate = { Date(timeIntervalSince1970: 0) }
            let window = NSWindow(contentView: view)
            window.setContentSize(CGSize(width: 400, height: 300))
            view.fit(to: window.contentLayoutRect.size)
            return window
        }
        try session.start()
        try await Task.sleep(for: .milliseconds(100))
        session.send(Array("\r".utf8))
        while bells.map(\.rings).reduce(0, +) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(bells.map(\.rings) == [1, 0])
        session.send(Array("\r".utf8))
        await session.waitForExit()
        #expect(windows.count == 2)
    }

    @Test func ringsTheBellAtMostTwiceASecond() async throws {
        let session = TerminalSession(
            running: "read a; printf '\\a'; read b; printf '\\a'; read c; printf '\\a'; read d")
        let view = TerminalContentView(session: session)
        let bell = Bell(view)
        var date = Date(timeIntervalSince1970: 0)
        view.currentDate = { date }
        let window = NSWindow(contentView: view)
        try session.start()
        for (count, interval, rings) in [(1, 0.0, 1), (2, 0.1, 1), (3, 0.5, 2)] {
            date += interval
            session.send(Array("\r".utf8))
            for await bellCount in Observations({ session.bellCount }) where bellCount == count {
                break
            }
            while bell.rings < rings {
                try Task.checkCancellation()
                await Task.yield()
            }
            for _ in 0 ..< 20 {
                await Task.yield()
            }
            #expect(bell.rings == rings)
        }
        session.send(Array("\r".utf8))
        await session.waitForExit()
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
        while weakView != nil || weakSession != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
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
