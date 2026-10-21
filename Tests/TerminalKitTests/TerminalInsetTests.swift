import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalInsetTests {
    @Test func fitsTheRowsBelowTheToolbar() async throws {
        let (scrollView, window) = toolbarWindow(running: "seq 1 200")
        let view = scrollView.terminalView
        let session = view.session
        #expect(scrollView.contentView.contentInsets.top > 0)
        #expect(session.terminal.rows == visibleRows(in: scrollView))
        #expect(view.convert(view.rect(row: 0, columns: 0 ..< 1), to: nil).maxY <= window.contentLayoutRect.maxY)
        try session.start()
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        let firstRow = view.rect(row: session.terminal.scrollback.count, columns: 0 ..< 1)
        #expect(scrollView.contentView.bounds.maxY == view.frame.height)
        #expect(view.convert(firstRow, to: nil).maxY <= window.contentLayoutRect.maxY)
    }

    @Test func growsWhenTheToolbarHides() throws {
        let (scrollView, window) = toolbarWindow(running: "exit")
        let session = scrollView.terminalView.session
        let rows = session.terminal.rows
        window.toolbar?.isVisible = false
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.terminal.rows > rows)
        #expect(session.terminal.rows == visibleRows(in: scrollView))
        window.toolbar?.isVisible = true
    }

    @Test func keepsTheTopBelowTheToolbarWhenOldLinesAreRemoved() async throws {
        let (scrollView, window) = toolbarWindow(running: "seq 1 10500; read line; seq 1 2000")
        let view = scrollView.terminalView
        let session = view.session
        try session.start()
        await session.waitForText("10500")
        scrollView.layoutSubtreeIfNeeded()
        view.scroll(CGPoint(x: 0, y: -scrollView.contentView.contentInsets.top))
        session.send("\r")
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.terminal.removedScrollbackCount > 0)
        #expect(view.convert(view.rect(row: 0, columns: 0 ..< 1), to: nil).maxY <= window.contentLayoutRect.maxY)
    }

    @Test func scrollsAboveTheBottomInsetWhenYouType() async throws {
        let session = TerminalSession(running: "seq 1 50; read line")
        let scrollView = TerminalScrollView(session: session)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForText("50")
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.terminal.rows == visibleRows(in: scrollView))
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height + 40)
        scrollView.terminalView.scroll(.zero)
        scrollView.terminalView.keyDown(with: try keyDown("\r"))
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height + 40)
        await session.waitForExit()
    }

    @Test func keepsThePositionWhenScrolledBackAboveTheBottomInset() async throws {
        let session = TerminalSession(running: "seq 1 50; read line; seq 51 100")
        let scrollView = TerminalScrollView(session: session)
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForText("50")
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: scrollView.contentView.bounds.minY - view.cellSize.height))
        let top = scrollView.contentView.bounds.minY
        session.send("\r")
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.minY == top)
    }

    @Test func reportsNoMoveUnderTheToolbar() async throws {
        let (scrollView, window) = toolbarWindow(
            running: "printf '\\033[?1003h\\033[?1006h'; stty raw -echo; echo ready; head -c 10 | tr '\\033' E")
        let view = scrollView.terminalView
        let session = view.session
        try session.start()
        await session.waitForText("ready")
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: -2, column: 1, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(await session.linesAfterExit().contains("E[<35;3;1M"))
        #expect(window.contentView === scrollView)
    }

    @Test func keepsTheFirstRowBelowTheFindBar() throws {
        let (scrollView, window) = toolbarWindow(running: "exit")
        let view = scrollView.terminalView
        let rows = view.session.terminal.rows
        scrollView.textFinder.performAction(.showFindInterface)
        scrollView.layoutSubtreeIfNeeded()
        let findBar = try #require(scrollView.findBarView)
        let findBarFrame = findBar.convert(findBar.bounds, to: nil)
        #expect(findBarFrame.maxY <= window.contentLayoutRect.maxY)
        #expect(view.session.terminal.rows < rows)
        #expect(view.session.terminal.rows == visibleRows(in: scrollView))
        #expect(view.convert(view.rect(row: 0, columns: 0 ..< 1), to: nil).maxY <= findBarFrame.minY)
    }
}

@MainActor
private func toolbarWindow(running script: String) -> (TerminalScrollView, NSWindow) {
    let scrollView = TerminalScrollView(session: TerminalSession(running: script))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: true
    )
    window.toolbar = NSToolbar(identifier: "Terminal")
    window.contentView = scrollView
    scrollView.layoutSubtreeIfNeeded()
    return (scrollView, window)
}

@MainActor
private func visibleRows(in scrollView: TerminalScrollView) -> Int {
    let insets = scrollView.contentView.contentInsets
    let height = scrollView.contentSize.height - insets.top - insets.bottom
    return Int((height - 2 * TerminalContentView.padding) / scrollView.terminalView.cellSize.height)
}
