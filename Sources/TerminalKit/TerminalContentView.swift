import AppKit
import TerminalCore

final class TerminalContentView: NSView {
    static let padding: CGFloat = 4
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    let session: TerminalSession

    var font = defaultFont {
        didSet {
            fonts = Fonts(font)
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

    private(set) var isFocused = false {
        didSet {
            guard isFocused != oldValue else {
                return
            }
            needsDisplay = true
            if session.terminal.usesFocusReporting {
                session.send(Array((isFocused ? "\u{1B}[I" : "\u{1B}[O").utf8))
            }
        }
    }
    var lastMousePosition: Terminal.Position?
    var scrollWheelLines: CGFloat = 0

    private var colors = Colors(.standard)
    private(set) var fonts = Fonts(defaultFont)
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

    struct Fonts {
        let regular: NSFont
        let bold: NSFont
        let italic: NSFont
        let boldItalic: NSFont

        init(_ font: NSFont) {
            regular = font
            bold = Self.font(font, traits: .bold)
            italic = Self.font(font, traits: .italic)
            boldItalic = Self.font(font, traits: [.bold, .italic])
        }

        func font(for style: Terminal.Style) -> NSFont {
            switch (style.isBold, style.isItalic) {
            case (false, false): regular
            case (true, false): bold
            case (false, true): italic
            case (true, true): boldItalic
            }
        }

        private static func font(_ font: NSFont, traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
            NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        if let newWindow {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowKeyStateDidChange),
                    name: name,
                    object: newWindow
                )
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.firstResponder === window || window.firstResponder is TerminalContentView {
            window.makeFirstResponder(self)
        }
        windowKeyStateDidChange()
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else {
            return false
        }
        isFocused = window?.isKeyWindow == true
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else {
            return false
        }
        isFocused = false
        return true
    }

    @objc private func windowKeyStateDidChange() {
        isFocused = window?.isKeyWindow == true && window?.firstResponder === self
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
            keyDownEvent = nil
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
            if let columns = selection?
                .columns(
                    inLine: terminal.removedScrollbackCount + row,
                    count: max(line.count, terminal.columns)
                )
            {
                selectionColor.setFill()
                rect(row: row, columns: columns).fill()
            }
            for (columns, style) in runs {
                drawText(line, columns: columns, row: row, style: style, foreground: colors(for: style).foreground)
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
        guard isFocused else {
            colors.cursor.setStroke()
            NSBezierPath(rect: cursor.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return
        }
        colors.cursor.setFill()
        cursor.fill(using: .sourceOver)
        let line = terminal.screen[terminal.cursor.row]
        let style = line[terminal.cursor.column].style
        drawText(
            line,
            columns: cursorColumns,
            row: terminal.scrollback.count + terminal.cursor.row,
            style: style,
            foreground: colors(for: style).background ?? colors.background
        )
    }

    private static func cellSize(of font: NSFont) -> CGSize {
        CGSize(
            width: ("M" as NSString).size(withAttributes: [.font: font]).width,
            height: ceil(font.ascender - font.descender + font.leading)
        )
    }

    func line(at row: Int) -> Terminal.Line {
        let terminal = session.terminal
        return row < terminal.scrollback.count
            ? terminal.scrollback[row] : terminal.screen[row - terminal.scrollback.count]
    }

    private var selectionColor: NSColor {
        isFocused ? colors.selection : .unemphasizedSelectedTextBackgroundColor
    }

    private static func runs(in line: Terminal.Line) -> [(columns: Range<Int>, style: Terminal.Style)] {
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

    private func drawText(
        _ line: Terminal.Line,
        columns: Range<Int>,
        row: Int,
        style: Terminal.Style,
        foreground: NSColor
    ) {
        guard !style.isHidden else {
            return
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: fonts.font(for: style),
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

    var cursorRect: CGRect {
        rect(row: session.terminal.scrollback.count + session.terminal.cursor.row, columns: cursorColumns)
    }

    private var cursorColumns: Range<Int> {
        let cursor = session.terminal.cursor
        let width = max(Int(session.terminal.screen[cursor.row][cursor.column].width), 1)
        return cursor.column ..< cursor.column + width
    }

    func fit(to size: CGSize) {
        let columns = max(Int((size.width - 2 * Self.padding) / cellSize.width), 1)
        if columns != session.terminal.columns {
            selection = nil
        }
        session.resize(columns: columns, rows: max(Int((size.height - 2 * Self.padding) / cellSize.height), 1))
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
