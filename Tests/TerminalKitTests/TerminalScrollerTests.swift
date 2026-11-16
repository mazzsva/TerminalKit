import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(3)))
struct TerminalScrollerTests {
    @Test func keepsTheColumnsOfALegacyScrollerWithoutScrollback() async throws {
        let session = TerminalSession(running: "seq 1 100")
        let scrollView = TerminalScrollView(session: session)
        scrollView.scrollerStyle = .legacy
        let window = NSWindow(contentView: scrollView)
        window.setContentSize(CGSize(width: 300, height: 200))
        scrollView.layoutSubtreeIfNeeded()
        let columns = session.terminal.columns
        try session.start()
        await session.waitForExit()
        for _ in 0 ..< 3 {
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
        }
        let cellWidth = scrollView.terminalView.cellSize.width
        #expect(session.terminal.columns == columns)
        #expect(
            columns == Int((scrollView.contentSize.width - 2 * TerminalContentView.padding) / cellWidth))
        #expect(scrollView.contentSize.width < 300)
    }

    @Test func keepsTheTranslucentBackgroundOfThePalette() throws {
        let scrollView = TerminalScrollView(session: TerminalSession(running: "exit"))
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        let representation = try #require(scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds))
        scrollView.cacheDisplay(in: scrollView.bounds, to: representation)
        let color = representation.colorAt(x: representation.pixelsWide / 2, y: representation.pixelsHigh / 2)
        #expect(try #require(color?.alphaComponent) < 1)
    }

    @Test func fitsTheSpaceBesideALegacyScroller() async throws {
        let session = TerminalSession(running: "seq 1 100")
        let scrollView = TerminalScrollView(session: session)
        scrollView.scrollerStyle = .legacy
        let window = NSWindow(contentView: scrollView)
        window.setContentSize(CGSize(width: 300, height: 200))
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForExit()
        for _ in 0 ..< 3 {
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
        }
        let cellWidth = scrollView.terminalView.cellSize.width
        #expect(scrollView.contentSize.width < 300)
        #expect(
            session.terminal.columns
                == Int((scrollView.contentSize.width - 2 * TerminalContentView.padding) / cellWidth))
    }
}
