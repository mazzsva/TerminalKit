import AppKit
import TerminalCore

final class TerminalContentView: NSView {
    static let padding: CGFloat = 4

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
    var selection: Selection? {
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
        scroll(CGPoint(x: 0, y: bounds.maxY - visibleRect.height))
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
        let terminal = session.terminal
        let lineCount = terminal.scrollback.count + terminal.rows
        let firstRow = max(Int((dirtyRect.minY - Self.padding) / cellSize.height), 0)
        let lastRow = min(Int((dirtyRect.maxY - Self.padding) / cellSize.height), lineCount - 1)
        for row in firstRow ..< max(lastRow + 1, firstRow) {
            let line = line(at: row)
            let runs = Self.runs(in: line)
            for (columns, style) in runs {
                if let background = colors(for: style).background {
                    background.setFill()
                    rect(row: row, columns: columns).fill()
                }
            }
            if let columns = selection?.columns(inLine: terminal.removedScrollbackCount + row, count: line.count) {
                selectionColor.setFill()
                rect(row: row, columns: columns).fill()
            }
            for (columns, style) in runs {
                drawText(line[columns], style: style, at: rect(row: row, columns: columns).origin)
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

    func line(at row: Int) -> [Terminal.Cell] {
        let terminal = session.terminal
        return row < terminal.scrollback.count
            ? terminal.scrollback[row] : terminal.screen[row - terminal.scrollback.count]
    }

    private var selectionColor: NSColor {
        window?.firstResponder === self ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
    }

    private static func runs(in line: [Terminal.Cell]) -> [(columns: Range<Int>, style: Terminal.Style)] {
        var runs: [(columns: Range<Int>, style: Terminal.Style)] = []
        var column = 0
        while column < line.count {
            let style = line[column].style
            let end = line[column...].firstIndex { $0.style != style } ?? line.count
            runs.append((column ..< end, style))
            column = end
        }
        return runs
    }

    private func colors(for style: Terminal.Style) -> (foreground: NSColor, background: NSColor?) {
        let foreground = NSColor.terminal(style.foreground) ?? .textColor
        let background = NSColor.terminal(style.background)
        return style.isInverse ? (background ?? .textBackgroundColor, foreground) : (foreground, background)
    }

    private func drawText(_ cells: ArraySlice<Terminal.Cell>, style: Terminal.Style, at origin: CGPoint) {
        guard !style.isHidden else {
            return
        }
        let foreground = colors(for: style).foreground
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
        let terminal = session.terminal
        return rect(
            row: terminal.scrollback.count + terminal.cursor.row,
            columns: terminal.cursor.column ..< terminal.cursor.column + 1
        )
    }

    func fit(to size: CGSize) {
        session.resize(
            columns: max(Int((size.width - 2 * Self.padding) / cellSize.width), 1),
            rows: max(Int((size.height - 2 * Self.padding) / cellSize.height), 1)
        )
        let lineCount = session.terminal.scrollback.count + session.terminal.rows
        setFrameSize(
            CGSize(width: size.width, height: max(size.height, CGFloat(lineCount) * cellSize.height + 2 * Self.padding))
        )
    }

    private func rect(row: Int, columns: Range<Int>) -> CGRect {
        CGRect(
            x: Self.padding + CGFloat(columns.lowerBound) * cellSize.width,
            y: Self.padding + CGFloat(row) * cellSize.height,
            width: CGFloat(columns.count) * cellSize.width,
            height: cellSize.height
        )
    }
}
