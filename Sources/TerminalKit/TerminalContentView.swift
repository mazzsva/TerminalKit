import AppKit

final class TerminalContentView: NSView {
    private static let padding: CGFloat = 4

    var session: TerminalSession {
        didSet {
            inputContext?.discardMarkedText()
            markedText = ""
            fitSession()
            needsDisplay = true
        }
    }

    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let cellSize: CGSize
    var markedText = "" {
        didSet {
            needsDisplay = true
        }
    }

    private var keyDownEvent: NSEvent?

    init(session: TerminalSession) {
        self.session = session
        cellSize = CGSize(
            width: ("M" as NSString).size(withAttributes: [.font: font]).width,
            height: ceil(font.ascender - font.descender + font.leading)
        )
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        keyDownEvent = event
        interpretKeyEvents([event])
        keyDownEvent = nil
    }

    override func doCommand(by selector: Selector) {
        if let input = keyDownEvent?.terminalInput {
            session.send(input)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitSession()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        for (row, line) in session.terminal.screen.enumerated() {
            let text = String(line.map(\.character))
            NSAttributedString(string: text, attributes: attributes).draw(at: rect(row: row, column: 0).origin)
        }

        let cursor = cursorRect
        guard markedText.isEmpty else {
            let text = NSAttributedString(
                string: markedText,
                attributes: attributes.merging([.underlineStyle: NSUnderlineStyle.single.rawValue]) { $1 }
            )
            NSColor.textBackgroundColor.setFill()
            CGRect(origin: cursor.origin, size: text.size()).fill()
            text.draw(at: cursor.origin)
            return
        }
        NSColor.textColor.withAlphaComponent(0.5).setFill()
        cursor.fill(using: .sourceOver)
    }

    var cursorRect: CGRect {
        rect(row: session.terminal.cursor.row, column: session.terminal.cursor.column)
    }

    private func fitSession() {
        session.resize(
            columns: max(Int((bounds.width - 2 * Self.padding) / cellSize.width), 1),
            rows: max(Int((bounds.height - 2 * Self.padding) / cellSize.height), 1)
        )
    }

    private func rect(row: Int, column: Int) -> CGRect {
        CGRect(
            x: Self.padding + CGFloat(column) * cellSize.width,
            y: Self.padding + CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
    }
}
