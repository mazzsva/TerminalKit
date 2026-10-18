import AppKit

final class TerminalScrollView: NSScrollView {
    let terminalView: TerminalContentView

    private var removedScrollbackCount = 0

    init(session: TerminalSession) {
        terminalView = TerminalContentView(session: session)
        super.init(frame: .zero)
        documentView = terminalView
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        let isAtBottom = contentView.bounds.maxY >= terminalView.frame.height
        let removedLines = terminalView.session.terminal.removedScrollbackCount - removedScrollbackCount
        removedScrollbackCount = terminalView.session.terminal.removedScrollbackCount
        super.layout()
        let size = contentSize
        terminalView.fit(to: size)
        if contentSize != size {
            terminalView.fit(to: contentSize)
        }
        if isAtBottom {
            terminalView.scroll(CGPoint(x: 0, y: terminalView.frame.height - contentSize.height))
        } else if removedLines > 0 {
            let offset = CGFloat(removedLines) * terminalView.cellSize.height
            terminalView.scroll(CGPoint(x: 0, y: max(contentView.bounds.minY - offset, 0)))
        }
    }
}
