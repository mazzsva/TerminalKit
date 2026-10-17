import AppKit
import TerminalCore

final class TerminalContentView: NSView {
    private static let padding: CGFloat = 4

    var session: TerminalSession {
        didSet {
            inputContext?.discardMarkedText()
            markedText = ""
            enclosingScrollView?.needsLayout = true
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.firstResponder === window {
            window.makeFirstResponder(self)
        }
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
        if let input = keyDownEvent?.terminalInput(applicationCursorKeys: session.terminal.usesApplicationCursorKeys) {
            session.send(input)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        for (row, line) in session.terminal.screen.enumerated() {
            var column = 0
            while column < line.count {
                let style = line[column].style
                let end = line[column...].firstIndex { $0.style != style } ?? line.count
                draw(line[column ..< end], style: style, at: rect(row: row, column: column).origin)
                column = end
            }
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

    private func draw(_ cells: ArraySlice<Terminal.Cell>, style: Terminal.Style, at origin: CGPoint) {
        var foreground = NSColor.terminal(style.foreground) ?? .textColor
        var background = NSColor.terminal(style.background)
        if style.isInverse {
            (foreground, background) = (background ?? .textBackgroundColor, foreground)
        }
        if let background {
            background.setFill()
            CGRect(x: origin.x, y: origin.y, width: cellSize.width * CGFloat(cells.count), height: cellSize.height)
                .fill()
        }
        guard !style.isHidden else {
            return
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style),
            .foregroundColor: style.isFaint ? foreground.withAlphaComponent(0.5) : foreground,
        ]
        if style.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        NSAttributedString(string: String(cells.map(\.character)), attributes: attributes).draw(at: origin)
    }

    private func font(for style: Terminal.Style) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.isBold {
            traits.insert(.bold)
        }
        if style.isItalic {
            traits.insert(.italic)
        }
        guard !traits.isEmpty else {
            return font
        }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    }

    var cursorRect: CGRect {
        rect(row: session.terminal.cursor.row, column: session.terminal.cursor.column)
    }

    func fit(to size: CGSize) {
        session.resize(
            columns: max(Int((size.width - 2 * Self.padding) / cellSize.width), 1),
            rows: max(Int((size.height - 2 * Self.padding) / cellSize.height), 1)
        )
        setFrameSize(size)
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
