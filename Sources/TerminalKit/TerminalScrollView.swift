import AppKit

final class TerminalScrollView: NSScrollView, NSMenuItemValidation {
    let terminalView: TerminalContentView
    var textFinder = NSTextFinder()

    private var removedScrollbackCount = 0

    init(session: TerminalSession) {
        terminalView = TerminalContentView(session: session)
        super.init(frame: .zero)
        documentView = terminalView
        hasVerticalScroller = true
        autohidesScrollers = false
        drawsBackground = false
        textFinder.client = terminalView
        textFinder.findBarContainer = self
        textFinder.isIncrementalSearchingEnabled = true
        session.isShown = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFindBarVisible: Bool {
        didSet {
            if oldValue, !isFindBarVisible, ownsFirstResponder {
                window?.makeFirstResponder(terminalView)
            }
        }
    }

    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? (sender as? NSView)?.tag,
            let action = NSTextFinder.Action(rawValue: tag)
        else {
            return
        }
        textFinder.performAction(action)
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        performTextFinderAction(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(performTextFinderAction(_:)), #selector(performFindPanelAction(_:)):
            NSTextFinder.Action(rawValue: menuItem.tag).map(textFinder.validateAction) ?? false
        default:
            true
        }
    }

    private var ownsFirstResponder: Bool {
        let responder = window?.firstResponder
        let view = (responder as? NSText)?.delegate as? NSView ?? responder as? NSView
        return view?.isDescendant(of: self) == true
    }

    private var isAtBottom: Bool {
        contentView.bounds.maxY >= terminalView.frame.height + contentView.contentInsets.bottom
    }

    override func setFrameSize(_ newSize: NSSize) {
        let isAtBottom = isAtBottom
        super.setFrameSize(newSize)
        if isAtBottom {
            terminalView.scrollToBottom()
        }
    }

    override func layout() {
        let isAtBottom = isAtBottom
        let removedLines = terminalView.session.terminal.removedScrollbackCount - removedScrollbackCount
        removedScrollbackCount = terminalView.session.terminal.removedScrollbackCount
        super.layout()
        let size = contentSize
        terminalView.fit(to: insetContentSize)
        if contentSize != size {
            terminalView.fit(to: insetContentSize)
        }
        if isAtBottom {
            terminalView.scrollToBottom()
        } else if removedLines > 0 {
            let offset = CGFloat(removedLines) * terminalView.cellSize.height
            terminalView.scroll(CGPoint(x: 0, y: contentView.bounds.minY - offset))
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        terminalView.hidesScrollback = isAtBottom
        terminalView.updateHoveredLink()
    }

    private var insetContentSize: CGSize {
        let insets = contentView.contentInsets
        return CGSize(
            width: contentSize.width - insets.left - insets.right,
            height: contentSize.height - insets.top - insets.bottom
        )
    }
}
