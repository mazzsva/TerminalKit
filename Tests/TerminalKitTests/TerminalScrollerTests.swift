import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalScrollerTests {
    @Test func fitsTheSpaceAfterALegacyScrollerHides() {
        let session = TerminalSession(running: "exit")
        let scrollView = TerminalScrollView(session: session)
        scrollView.scrollerStyle = .legacy
        let window = NSWindow(contentView: scrollView)
        scrollView.layoutSubtreeIfNeeded()
        window.setContentSize(CGSize(width: 300, height: 200))
        for _ in 0 ..< 3 {
            scrollView.layoutSubtreeIfNeeded()
        }
        let cellWidth = scrollView.terminalView.cellSize.width
        #expect(
            session.terminal.columns
                == Int((scrollView.contentSize.width - 2 * TerminalContentView.padding) / cellWidth))
        #expect(scrollView.terminalView.frame.width == scrollView.contentSize.width)
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
