import AppKit
import TerminalCore

final class TerminalContentView: NSView {
    static let padding: CGFloat = 4
    static let minimumColumns = 10
    static let minimumRows = 2
    static let maximumColumns = 1_000
    static let maximumRows = 1_000
    static let cursorThickness: CGFloat = 2
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
            scheduleAccessibilityNotification()
        }
    }
    var cachedAccessibilityText: AccessibilityText?
    var isAccessibilityNotificationScheduled = false
    var postAccessibilityNotifications = { (view: NSView) in
        NSAccessibility.post(element: view, notification: .valueChanged)
        NSAccessibility.post(element: view, notification: .selectedTextChanged)
    }
    private var accessibilityRevision = 0

    private(set) var isFocused = false {
        didSet {
            guard isFocused != oldValue else {
                return
            }
            needsDisplay = true
            if isFocused, session.sizingView !== self {
                session.sizingView = self
            }
            if session.liveTerminal.usesFocusReporting {
                session.send(Array((isFocused ? "\u{1B}[I" : "\u{1B}[O").utf8))
            }
        }
    }
    var ringBell = { NSSound.beep() }
    var currentDate = { Date() }
    var performLinkAction = performWithWorkspace
    var hoveredLink: Link? {
        didSet {
            guard hoveredLink != oldValue else {
                return
            }
            needsDisplay = true
            if (hoveredLink == nil) != (oldValue == nil) {
                (hoveredLink == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
            }
        }
    }
    var hoveredLinkRevision = 0
    var isOpeningLink = false
    private var fittedColumns: Int?
    var lastMousePosition: Terminal.Position?
    var scrollWheelLines: CGFloat = 0

    private var colors = Colors(.standard)
    private(set) var fonts = Fonts(defaultFont)
    private var keyDownEvent: NSEvent?
    private var bellTask: Task<Void, Never>?
    private var lastBellDate: Date?

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
            ansiColors =
                (palette.ansiColors.prefix(16) + TerminalPalette.standard.ansiColors.dropFirst(palette.ansiColors.count))
                .map(NSColor.init)
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
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
        )
        registerForDraggedTypes([.fileURL, .string])
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
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        if let newWindow {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(releaseSize),
                name: NSWindow.willCloseNotification,
                object: newWindow
            )
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
        if window == nil {
            releaseSize()
        }
        if let window, window.firstResponder === window || window.firstResponder is TerminalContentView {
            window.makeFirstResponder(self)
        }
        windowKeyStateDidChange()
        bellTask?.cancel()
        bellTask = nil
        if window != nil {
            bellTask = Task { [weak self, session] in
                for await _ in Observations({ session.bellCount }).dropFirst() {
                    self?.bellDidRing()
                }
            }
        }
    }

    static func ringsBell(at date: Date, lastBellDate: Date?) -> Bool {
        lastBellDate.map { date.timeIntervalSince($0) >= 0.5 } ?? true
    }

    private func bellDidRing() {
        let date = currentDate()
        guard session.sizingView == nil || session.sizingView === self,
            Self.ringsBell(at: date, lastBellDate: lastBellDate)
        else {
            return
        }
        lastBellDate = date
        ringBell()
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

    @objc private func releaseSize() {
        if session.sizingView === self {
            session.sizingView = nil
        }
    }

    @objc private func windowKeyStateDidChange() {
        isFocused = window?.isKeyWindow == true && window?.firstResponder === self
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
            let key = event.charactersIgnoringModifiers?.unicodeScalars.first,
            [NSUpArrowFunctionKey, NSDownArrowFunctionKey].contains(Int(key.value))
        {
            scrollToPrompt(isPrevious: Int(key.value) == NSUpArrowFunctionKey)
            return
        }
        guard !event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        scrollToBottom()
        if markedText.isEmpty, let input = event.controlInput {
            session.send(input)
            return
        }
        if let input = event.wordMovementInput {
            session.send(input)
            return
        }
        if usesOptionAsMetaKey, event.modifierFlags.contains(.option),
            let input = event.metaInput(applicationCursorKeys: session.liveTerminal.usesApplicationCursorKeys)
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
        if let input = keyDownEvent?
            .terminalInput(applicationCursorKeys: session.liveTerminal.usesApplicationCursorKeys)
        {
            session.send(input)
            keyDownEvent = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if accessibilityRevision != session.revision {
            accessibilityRevision = session.revision
            scheduleAccessibilityNotification()
            textFinder?.noteClientStringWillChange()
        }
        colors.background.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.foreground]
        let terminal = session.terminal
        let graphemes = terminal.graphemes
        let lineCount = terminal.scrollback.count + terminal.rows
        let firstRow = max(Int((dirtyRect.minY - Self.padding) / cellSize.height), 0)
        let lastRow = min(Int((dirtyRect.maxY - Self.padding) / cellSize.height), lineCount - 1)
        for row in firstRow ..< max(lastRow + 1, firstRow) {
            let line = line(at: row, in: terminal)
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
                drawText(
                    line,
                    columns: columns,
                    row: row,
                    style: style,
                    foreground: colors(for: style).foreground,
                    graphemes: graphemes
                )
            }
        }

        if let hoveredLink, hoveredLinkRevision == session.revision {
            colors.foreground.setFill()
            for span in hoveredLink.spans {
                let rect = rect(row: span.row, columns: span.columns)
                CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
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
        switch terminal.cursorShape {
        case .underline:
            CGRect(
                x: cursor.minX, y: cursor.maxY - Self.cursorThickness, width: cursor.width, height: Self.cursorThickness
            )
            .fill(using: .sourceOver)
            return
        case .bar:
            CGRect(x: cursor.minX, y: cursor.minY, width: Self.cursorThickness, height: cursor.height)
                .fill(using: .sourceOver)
            return
        case .block:
            cursor.fill(using: .sourceOver)
        }
        let line = terminal.screen[terminal.cursor.row]
        let style = line[terminal.cursor.column].style
        drawText(
            line,
            columns: cursorColumns,
            row: terminal.scrollback.count + terminal.cursor.row,
            style: style,
            foreground: colors(for: style).background ?? colors.background,
            graphemes: graphemes
        )
    }

    private static func cellSize(of font: NSFont) -> CGSize {
        CGSize(
            width: ("M" as NSString).size(withAttributes: [.font: font]).width,
            height: ceil(font.ascender - font.descender + font.leading)
        )
    }

    func line(at row: Int) -> Terminal.Line {
        line(at: row, in: session.terminal)
    }

    func line(at row: Int, in terminal: Terminal) -> Terminal.Line {
        row < terminal.scrollback.count ? terminal.scrollback[row] : terminal.screen[row - terminal.scrollback.count]
    }

    private var selectionColor: NSColor {
        isFocused ? colors.selection : .unemphasizedSelectedTextBackgroundColor
    }

    static func runs(in line: Terminal.Line) -> [(columns: Range<Int>, style: Terminal.Style)] {
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

    func drawText(
        _ line: Terminal.Line,
        columns: Range<Int>,
        row: Int,
        style: Terminal.Style,
        foreground: NSColor,
        graphemes: Terminal.Graphemes
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
                line[column ..< columns.upperBound].firstIndex { $0.width != 1 || !$0.isASCII }
                ?? columns.upperBound
            if end > column {
                let text = String(line[column ..< end].map(graphemes.character(of:)))
                NSAttributedString(string: text, attributes: attributes)
                    .draw(at: rect(row: row, columns: column ..< end).origin)
                column = end
            } else {
                if line[column].width > 0 {
                    NSAttributedString(string: String(graphemes.character(of: line[column])), attributes: attributes)
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
        _ = session.sizingViewChangeCount
        let columns = (size.width - 2 * Self.padding) / cellSize.width
        let rows = (size.height - 2 * Self.padding) / cellSize.height
        let canSize = columns >= CGFloat(Self.minimumColumns) && rows >= CGFloat(Self.minimumRows)
        if !canSize, session.sizingView === self {
            session.sizingView = nil
        }
        if canSize, session.sizingView == nil || session.sizingView?.window == nil && window != nil {
            session.sizingView = self
        }
        if session.sizingView === self {
            session.resize(
                columns: Int(min(columns, CGFloat(Self.maximumColumns))),
                rows: Int(min(rows, CGFloat(Self.maximumRows)))
            )
        }
        if session.terminal.columns != fittedColumns {
            selection = nil
            fittedColumns = session.terminal.columns
        }
        let lineCount = session.terminal.scrollback.count + session.terminal.rows
        setFrameSize(
            CGSize(width: size.width, height: max(size.height, CGFloat(lineCount) * cellSize.height + 2 * Self.padding))
        )
    }

    func rect(row: Int, columns: Range<Int>) -> CGRect {
        CGRect(
            x: Self.padding + CGFloat(columns.lowerBound) * cellSize.width,
            y: Self.padding + CGFloat(row) * cellSize.height,
            width: CGFloat(columns.count) * cellSize.width,
            height: cellSize.height
        )
    }
}
