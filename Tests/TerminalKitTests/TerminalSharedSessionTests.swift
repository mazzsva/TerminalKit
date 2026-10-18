import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSharedSessionTests {
    private let session = TerminalSession(running: "exit")

    @Test func letsOneViewSizeTheSession() {
        let (narrow, narrowWindow) = scrollView(width: 300, in: NSWindow(contentView: NSView()))
        let (wide, wideWindow) = scrollView(width: 700, in: NSWindow(contentView: NSView()))
        for _ in 0 ..< 3 {
            narrow.layoutSubtreeIfNeeded()
            wide.layoutSubtreeIfNeeded()
        }
        #expect(session.terminal.columns == columns(of: narrow))
        #expect(wide.terminalView.frame.width == wide.contentSize.width)
        #expect(narrowWindow.contentView === narrow && wideWindow.contentView === wide)
    }

    @Test func givesTheSizeToTheViewWithTheFocus() {
        let (narrow, narrowWindow) = scrollView(width: 300, in: KeyWindow(contentView: NSView()))
        let (wide, wideWindow) = scrollView(width: 700, in: KeyWindow(contentView: NSView()))
        wideWindow.isKey = false
        narrowWindow.isKey = false
        narrowWindow.isKey = true
        narrow.layoutSubtreeIfNeeded()
        wide.layoutSubtreeIfNeeded()
        #expect(session.terminal.columns == columns(of: narrow))

        narrowWindow.isKey = false
        wideWindow.isKey = true
        wide.layoutSubtreeIfNeeded()
        narrow.layoutSubtreeIfNeeded()
        #expect(session.terminal.columns == columns(of: wide))

        wideWindow.isKey = false
        narrowWindow.isKey = true
        wide.layoutSubtreeIfNeeded()
        narrow.layoutSubtreeIfNeeded()
        #expect(session.terminal.columns == columns(of: narrow))
    }

    @Test func givesTheSizeBackWhenTheViewLeavesItsWindow() {
        let (narrow, narrowWindow) = scrollView(width: 300, in: NSWindow(contentView: NSView()))
        let (wide, _) = scrollView(width: 700, in: NSWindow(contentView: NSView()))
        narrow.layoutSubtreeIfNeeded()
        narrowWindow.contentView = NSView()
        #expect(session.sizingView == nil)
        wide.layoutSubtreeIfNeeded()
        #expect(session.terminal.columns == columns(of: wide))
    }

    @Test func givesTheSizeBackWhenTheWindowCloses() {
        let (narrow, narrowWindow) = scrollView(width: 300, in: NSWindow(contentView: NSView()))
        let (wide, _) = scrollView(width: 700, in: NSWindow(contentView: NSView()))
        narrow.layoutSubtreeIfNeeded()
        narrowWindow.close()
        #expect(session.sizingView == nil)
        wide.layoutSubtreeIfNeeded()
        #expect(session.terminal.columns == columns(of: wide))
    }

    @Test func keepsTheSizeWhenAnotherViewLeavesItsWindow() {
        let (narrow, _) = scrollView(width: 300, in: NSWindow(contentView: NSView()))
        let (wide, wideWindow) = scrollView(width: 700, in: NSWindow(contentView: NSView()))
        narrow.layoutSubtreeIfNeeded()
        wide.layoutSubtreeIfNeeded()
        wideWindow.contentView = NSView()
        #expect(session.sizingView === narrow.terminalView)
    }

    @Test func laysOutTheViewThatTakesTheFocus() {
        let (narrow, narrowWindow) = scrollView(width: 300, in: KeyWindow(contentView: NSView()))
        let (wide, wideWindow) = scrollView(width: 700, in: KeyWindow(contentView: NSView()))
        wideWindow.isKey = false
        narrowWindow.isKey = false
        narrowWindow.isKey = true
        narrow.layoutSubtreeIfNeeded()
        wide.layoutSubtreeIfNeeded()
        #expect(!wide.needsLayout)
        narrowWindow.isKey = false
        wideWindow.isKey = true
        #expect(wide.needsLayout)
    }

    @Test func takesTheSizeFromAViewWithoutAWindow() {
        let detached = TerminalScrollView(session: session)
        detached.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        detached.layoutSubtreeIfNeeded()
        let (wide, _) = scrollView(width: 700, in: NSWindow(contentView: NSView()))
        wide.layoutSubtreeIfNeeded()
        #expect(session.terminal.columns == columns(of: wide))
    }

    @Test func dropsTheSelectionWhenAnotherViewChangesTheWidth() {
        let (narrow, narrowWindow) = scrollView(width: 300, in: KeyWindow(contentView: NSView()))
        let (wide, wideWindow) = scrollView(width: 700, in: KeyWindow(contentView: NSView()))
        wideWindow.isKey = false
        narrowWindow.isKey = false
        narrowWindow.isKey = true
        narrow.layoutSubtreeIfNeeded()
        narrow.terminalView.selection = .init(anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 2))
        narrowWindow.isKey = false
        wideWindow.isKey = true
        wide.layoutSubtreeIfNeeded()
        narrow.layoutSubtreeIfNeeded()
        #expect(narrow.terminalView.selection == nil)
    }

    private func scrollView<Window: NSWindow>(width: CGFloat, in window: Window) -> (TerminalScrollView, Window) {
        let scrollView = TerminalScrollView(session: session)
        window.contentView = scrollView
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: width, height: 200))
        return (scrollView, window)
    }

    private func columns(of scrollView: TerminalScrollView) -> Int {
        Int((scrollView.contentSize.width - 2 * TerminalContentView.padding) / scrollView.terminalView.cellSize.width)
    }
}
