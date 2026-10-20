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
        autohidesScrollers = true
        drawsBackground = false
        textFinder.client = terminalView
        textFinder.findBarContainer = self
        textFinder.isIncrementalSearchingEnabled = true
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard ownsFirstResponder, event.modifierFlags.intersection([.command, .option, .control]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        let action: NSTextFinder.Action? =
            switch (event.charactersIgnoringModifiers?.lowercased(), event.modifierFlags.contains(.shift)) {
            case ("f", false): .showFindInterface
            case ("g", false): .nextMatch
            case ("g", true): .previousMatch
            case ("e", false): .setSearchString
            default: nil
            }
        guard let action else {
            return super.performKeyEquivalent(with: event)
        }
        textFinder.performAction(action)
        return true
    }

    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag, let action = NSTextFinder.Action(rawValue: tag)
        else {
            return
        }
        textFinder.performAction(action)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performTextFinderAction(_:)) else {
            return true
        }
        return NSTextFinder.Action(rawValue: menuItem.tag).map(textFinder.validateAction) ?? false
    }

    private var ownsFirstResponder: Bool {
        let responder = window?.firstResponder
        let view = (responder as? NSText)?.delegate as? NSView ?? responder as? NSView
        return view?.isDescendant(of: self) == true
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
