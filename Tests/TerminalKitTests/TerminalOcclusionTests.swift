import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalOcclusionTests {
    @Test func drawsNothingWhileItsWindowIsNotVisible() async throws {
        let session = TerminalSession(running: "stty -echo; printf a; read x; printf b; read y")
        let scrollView = TerminalScrollView(session: session)
        let view = scrollView.terminalView
        let window = OcclusionWindow(contentView: scrollView)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForText("a")
        view.layer?.displayIfNeeded()
        let start = try image(of: view)
        while view.isAccessibilityNotificationScheduled {
            try await Task.sleep(for: .milliseconds(10))
        }
        var posts = 0
        view.postAccessibilityNotifications = { _ in posts += 1 }
        let drawCount = view.drawCount

        window.isUncovered = false
        session.send(Array("\r".utf8))
        await session.waitForText("ab")
        view.needsDisplay = true
        view.layer?.displayIfNeeded()
        #expect(view.drawCount == drawCount)
        for _ in 0 ..< 100 where posts == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(posts == 1)

        window.isUncovered = true
        view.layer?.displayIfNeeded()
        #expect(view.drawCount == drawCount + 1)
        #expect(try image(of: view) != start)
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }
}

private final class OcclusionWindow: NSWindow {
    var isUncovered = true {
        didSet {
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
        }
    }

    override var occlusionState: NSWindow.OcclusionState {
        isUncovered ? .visible : []
    }
}

@MainActor
private func image(of view: NSView) throws -> Data {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return try #require(representation.tiffRepresentation)
}
