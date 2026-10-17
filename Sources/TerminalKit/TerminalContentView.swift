import AppKit
import TerminalCore

final class TerminalContentView: NSView {
    static let padding: CGFloat = 4
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    var session: TerminalSession {
        didSet {
            inputContext?.discardMarkedText()
            markedText = ""
            enclosingScrollView?.needsLayout = true
            needsDisplay = true
        }
    }

    var font = defaultFont {
        didSet {
            cellSize = Self.cellSize(of: font)
            enclosingScrollView?.needsLayout = true
            needsDisplay = true
        }
    }
    private(set) var cellSize: CGSize
    var palette = TerminalPalette.standard {
        didSet {
            colors = Colors(palette)
            needsDisplay = true
        }
    }
    var usesOptionAsMetaKey = false
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

    private var colors = Colors(.standard)
    private var keyDownEvent: NSEvent?

    private struct Colors {
        let foreground: NSColor
        let background: NSColor
        let cursor: NSColor
        let selection: NSColor
        let ansiColors: [NSColor]

        init(_ palette: TerminalPalette) {
            foreground = NSColor(palette.foreground)
            background = NSColor(palette.background)
            cursor = NSColor(palette.cursor)
            selection = NSColor(palette.selection)
            ansiColors = palette.ansiColors.map(NSColor.init)
        }
    }

    init(session: TerminalSession) {
        self.session = session
        cellSize = Self.cellSize(of: font)
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
        scrollToBottom()
        if let input = event.wordMovementInput {
            session.send(input)
            return
        }
        if usesOptionAsMetaKey, event.modifierFlags.contains(.option),
            let input = event.metaInput(applicationCursorKeys: session.terminal.usesApplicationCursorKeys)
        {
            session.send(input)
            return
        }
        keyDownEvent = event
        interpretKeyEvents([event])
        keyDownEvent = nil
    }

    func scrollToBottom() {
        scroll(CGPoint(x: 0, y: bounds.maxY - visibleRect.height))
    }

    override func doCommand(by selector: Selector) {
        if let input = keyDownEvent?.terminalInput(applicationCursorKeys: session.terminal.usesApplicationCursorKeys) {
            session.send(input)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        colors.background.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.foreground]
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
                drawText(line, columns: columns, row: row, style: style)
            }
        }

        let cursor = cursorRect
        guard markedText.isEmpty else {
            let text = NSAttributedString(
                string: markedText,
                attributes: attributes.merging([.underlineStyle: NSUnderlineStyle.single.rawValue]) { $1 }
            )
            colors.background.setFill()
            CGRect(origin: cursor.origin, size: text.size()).fill()
            text.draw(at: cursor.origin)
            return
        }
        guard terminal.isCursorVisible else {
            return
        }
        colors.cursor.setFill()
        cursor.fill(using: .sourceOver)
    }

    private static func cellSize(of font: NSFont) -> CGSize {
        CGSize(
            width: ("M" as NSString).size(withAttributes: [.font: font]).width,
            height: ceil(font.ascender - font.descender + font.leading)
        )
    }

    func line(at row: Int) -> [Terminal.Cell] {
        let terminal = session.terminal
        return row < terminal.scrollback.count
            ? terminal.scrollback[row] : terminal.screen[row - terminal.scrollback.count]
    }

    private var selectionColor: NSColor {
        window?.firstResponder === self ? colors.selection : .unemphasizedSelectedTextBackgroundColor
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
        let foreground = NSColor.terminal(style.foreground, ansiColors: colors.ansiColors) ?? colors.foreground
        let background = NSColor.terminal(style.background, ansiColors: colors.ansiColors)
        return style.isInverse ? (background ?? colors.background, foreground) : (foreground, background)
    }

    private func drawText(_ line: [Terminal.Cell], columns: Range<Int>, row: Int, style: Terminal.Style) {
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
        var column = columns.lowerBound
        while column < columns.upperBound {
            let end =
                line[column ..< columns.upperBound].firstIndex { $0.width != 1 || !$0.character.isASCII }
                ?? columns.upperBound
            if end > column {
                let text = String(line[column ..< end].map(\.character))
                NSAttributedString(string: text, attributes: attributes)
                    .draw(at: rect(row: row, columns: column ..< end).origin)
                column = end
            } else {
                if line[column].width > 0 {
                    NSAttributedString(string: String(line[column].character), attributes: attributes)
                        .draw(at: rect(row: row, columns: column ..< column + 1).origin)
                }
                column += 1
            }
        }
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
