import AppKit

final class TerminalScrollView: NSScrollView {
    let terminalView: TerminalContentView

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
        super.layout()
        terminalView.fit(to: contentSize)
        if isAtBottom {
            terminalView.scroll(CGPoint(x: 0, y: terminalView.frame.height - contentSize.height))
        }
    }
}
