import AppKit
import TerminalCore

final class TerminalContentView: NSView {
    static let padding: CGFloat = 10
    static let topPadding: CGFloat = 7
    static let bottomPadding: CGFloat = 10
    static let minimumColumns = 10
    static let minimumRows = 2
    static let maximumColumns = 1_000
    static let maximumRows = 1_000
    static let cursorThickness: CGFloat = 2
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    let session: TerminalSession

    var font = defaultFont {
        didSet {
            fonts = Fonts(font)
            cellSize = Self.cellSize(of: font)
            updateHoveredLink()
            enclosingScrollView?.needsLayout = true
            needsDisplay = true
        }
    }
    private(set) var cellSize: CGSize
    var palette = TerminalPalette.standard {
        didSet {
            colors = Colors(palette)
            changedColorsCache = nil
            updateReportedColors()
            needsDisplay = true
        }
    }
    private(set) var reportedColors: Terminal.DefaultColors?
    var usesOptionAsMetaKey = false
    var markedString = NSAttributedString() {
        didSet {
            needsDisplay = true
        }
    }
    var markedSelection = NSRange(location: 0, length: 0)
    var insertedText = ""
    var markedText: String {
        markedString.string
    }
    var selection: Selection? {
        didSet {
            guard selection != oldValue else {
                return
            }
            needsDisplay = true
            scheduleAccessibilityNotification()
        }
    }
    var selectionOrigin: Selection?
    var clickLocation: CGPoint?
    var selectionClickCount = 1
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
            if session.liveTerminal.usesFocusReporting {
                session.send(Array((isFocused ? "\u{1B}[I" : "\u{1B}[O").utf8))
            }
        }
    }
    var ringBell = { NSSound.beep() }
    var hidePointer = { NSCursor.setHiddenUntilMouseMoves(true) }
    var currentDate = { Date() }
    var currentModifierFlags = { NSEvent.modifierFlags }
    var pressedMouseButtons = { NSEvent.pressedMouseButtons }
    var performLinkAction = performWithWorkspace
    var hoveredLink: Link? {
        didSet {
            guard hoveredLink != oldValue else {
                return
            }
            needsDisplay = true
        }
    }
    var hoveredLinkRevision = 0
    var hidesScrollback = false {
        didSet {
            guard hidesScrollback != oldValue else {
                return
            }
            needsDisplay = true
        }
    }
    var isOpeningLink = false
    private var fittedColumns: Int?
    var lastMousePosition: Terminal.Position?
    var autoscrollTask: Task<Void, Never>?
    var autoscrollClock: any Clock<Duration> = ContinuousClock()

    private var colors = Colors(.standard)
    private var changedColorsCache: (changes: Terminal.ChangedColors, isReversed: Bool, colors: Colors)?
    private(set) var fonts = Fonts(defaultFont)
    private(set) var keyDownEvent: NSEvent?
    var isNumLockOn = false
    var reportedButtons: Set<Int> = []
    var presentsAlert: @MainActor (NSAlert, NSWindow?) -> NSApplication.ModalResponse = { alert, window in
        guard let window else {
            return alert.runModal()
        }
        alert.beginSheetModal(for: window)
        return .alertFirstButtonReturn
    }
    private var bellTask: Task<Void, Never>?
    private var flagsMonitor: Any?
    private var lastBellDate: Date?
    private var joinNumber = 0
    private static var joinCount = 0
    private(set) var drawCount = 0
    private var isOccluded = false

    private struct Colors {
        let foreground: NSColor
        let background: NSColor
        let cursor: NSColor
        let selection: NSColor
        let bold: NSColor
        let backgroundAlpha: CGFloat
        let ansiColors: [NSColor]
        private let changedColors: [UInt8: NSColor]
        private let cache = ColorCache()

        private final class ColorCache {
            var colors: [Terminal.Color: NSColor] = [:]
        }

        func color(_ color: Terminal.Color) -> NSColor? {
            if case .indexed(let index) = color, let changed = changedColors[index] {
                return changed
            }
            if let cached = cache.colors[color] {
                return cached
            }
            let resolved = NSColor.terminal(color, ansiColors: ansiColors)
            if cache.colors.count >= 4_096 {
                cache.colors.removeAll()
            }
            cache.colors[color] = resolved
            return resolved
        }

        func colors(for style: Terminal.Style) -> (foreground: NSColor, background: NSColor?) {
            let indexed = color(style.foreground)
            let foreground = indexed ?? (style.isBold ? bold : self.foreground)
            let background = color(style.background)
            guard style.isInverse else {
                return (foreground, background)
            }
            return (
                background ?? self.background.withAlphaComponent(1),
                indexed == nil ? foreground.withAlphaComponent(backgroundAlpha) : foreground
            )
        }

        init(
            _ palette: TerminalPalette,
            isReversed: Bool = false,
            changes: Terminal.ChangedColors = Terminal.ChangedColors()
        ) {
            let paletteForeground = NSColor(palette.foreground)
            let paletteBackground = NSColor(palette.background)
            let paletteCursor = NSColor(palette.cursor)
            foreground = isReversed ? paletteBackground.withAlphaComponent(1) : paletteForeground
            background = isReversed ? paletteForeground : paletteBackground
            backgroundAlpha = paletteBackground.alphaComponent
            bold = isReversed ? foreground : NSColor(palette.bold)
            cursor = changes.cursor.map { NSColor($0, alpha: paletteCursor.alphaComponent) } ?? paletteCursor
            selection = NSColor(palette.selection)
            var ansiColors =
                (palette.ansiColors.prefix(16) + TerminalPalette.standard.ansiColors.dropFirst(palette.ansiColors.count))
                .map(NSColor.init)
            var changedColors: [UInt8: NSColor] = [:]
            for (index, color) in changes.indexed {
                if index < 16 {
                    ansiColors[Int(index)] = NSColor(color)
                } else {
                    changedColors[index] = NSColor(color)
                }
            }
            self.changedColors = changedColors
            self.ansiColors = ansiColors
        }
    }

    struct Fonts {
        let regular: NSFont
        let bold: NSFont
        let italic: NSFont
        let boldItalic: NSFont
        let glyphs = GlyphCache()

        init(_ font: NSFont) {
            regular = font
            bold = Self.font(font, traits: .bold)
            italic = Self.font(font, traits: .italic)
            boldItalic = Self.font(font, traits: [.bold, .italic])
        }

        func index(for style: Terminal.Style) -> Int {
            (style.isBold ? 1 : 0) + (style.isItalic ? 2 : 0)
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
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
        )
        registerForDraggedTypes([.fileURL, .string])
        NSApp?.registerServicesMenuSendTypes([.string], returnTypes: [])
        updateReportedColors()
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        changedColorsCache = nil
        updateReportedColors()
    }

    private func currentColors(for terminal: Terminal) -> Colors {
        guard terminal.usesReverseVideo || !terminal.changedColors.isEmpty else {
            return colors
        }
        if let cache = changedColorsCache, cache.changes == terminal.changedColors,
            cache.isReversed == terminal.usesReverseVideo
        {
            return cache.colors
        }
        let colors = Colors(palette, isReversed: terminal.usesReverseVideo, changes: terminal.changedColors)
        changedColorsCache = (terminal.changedColors, terminal.usesReverseVideo, colors)
        return colors
    }

    private func updateReportedColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let foreground = colors.foreground.terminalRGB,
                let background = colors.background.terminalRGB,
                let cursor = colors.cursor.terminalRGB
            else {
                reportedColors = nil
                return
            }
            reportedColors = Terminal.DefaultColors(foreground: foreground, background: background, cursor: cursor)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let window, window.firstResponder === self, let contentView = window.contentView {
            Task {
                if let view = Self.contentViews(in: contentView).filter({ !$0.isHiddenOrHasHiddenAncestor })
                    .max(by: { $0.joinNumber < $1.joinNumber }),
                    let window = view.window, window.firstResponder === window
                {
                    window.makeFirstResponder(view)
                }
            }
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        isOccluded = false
        if let newWindow {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowKeyStateDidChange),
                    name: name,
                    object: newWindow
                )
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowOcclusionStateDidChange),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: newWindow
            )
        }
    }

    @objc private func windowOcclusionStateDidChange() {
        isOccluded = window?.occlusionState.contains(.visible) == false
        if !isOccluded {
            needsDisplay = true
        }
    }

    override var needsDisplay: Bool {
        get {
            super.needsDisplay
        }
        set {
            if !isOccluded || !newValue {
                super.needsDisplay = newValue
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.firstResponder === window {
            window.makeFirstResponder(self)
        } else if window?.firstResponder is TerminalContentView {
            Task { [weak self] in
                if let window = self?.window, window.firstResponder === window {
                    window.makeFirstResponder(self)
                }
            }
        }
        windowKeyStateDidChange()
        bellTask?.cancel()
        bellTask = nil
        autoscrollTask?.cancel()
        autoscrollTask = nil
        flagsMonitor.map(NSEvent.removeMonitor)
        flagsMonitor = nil
        if window != nil {
            session.sizingView = self
            Self.joinCount += 1
            joinNumber = Self.joinCount
            bellTask = Task { [weak self, session] in
                for await _ in Observations({ session.bellCount }).dropFirst() {
                    self?.bellDidRing()
                }
            }
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.updateHoveredLink()
                return event
            }
        }
    }

    private static func contentViews(in view: NSView) -> [TerminalContentView] {
        (view as? TerminalContentView).map { [$0] } ?? view.subviews.flatMap(contentViews(in:))
    }

    static func ringsBell(at date: Date, lastBellDate: Date?) -> Bool {
        lastBellDate.map { date.timeIntervalSince($0) >= 0.5 } ?? true
    }

    private func bellDidRing() {
        let date = currentDate()
        guard Self.ringsBell(at: date, lastBellDate: lastBellDate) else {
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

    @objc private func windowKeyStateDidChange() {
        isFocused = window?.isKeyWindow == true && window?.firstResponder === self
        hoveredLink = nil
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if markedText.isEmpty, !session.liveTerminal.isAlternateScreenActive, scrollsView(for: event) {
            return
        }
        if markedText.isEmpty, event.charactersIgnoringModifiers == "\u{F739}",
            modifiers.isDisjoint(with: [.shift, .control, .option])
        {
            isNumLockOn.toggle()
            return
        }
        let input = markedText.isEmpty ? keyInput(event) : .text
        if case .scroll = input {
            scrollView(for: event.specialKey)
            return
        }
        let sendsBytes = if case .bytes = input { true } else { false }
        guard !modifiers.contains(.command) || sendsBytes else {
            if markedText.isEmpty, modifiers == .command, event.charactersIgnoringModifiers == "k" {
                session.clearToStart()
            } else {
                super.keyDown(with: event)
            }
            return
        }
        hidePointer()
        scrollToBottom()
        switch input {
        case .bytes(let bytes):
            insertedText = ""
            session.send(bytes)
        case .nothing, .scroll:
            insertedText = ""
        case .text:
            keyDownEvent = event
            interpretKeyEvents([event])
            keyDownEvent = nil
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard window?.firstResponder === self, modifiers.contains(.control), !modifiers.contains(.command),
            let key = event.charactersIgnoringModifiers, ["\t", "\u{19}", "\u{1B}"].contains(key)
        else {
            return super.performKeyEquivalent(with: event)
        }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        keyDown(with: event)
        return true
    }

    func keyInput(_ event: NSEvent) -> TerminalKeyInput {
        let terminal = session.liveTerminal
        return event.terminalKeyInput(
            TerminalKeyModes(
                usesOptionAsMetaKey: usesOptionAsMetaKey,
                usesApplicationCursorKeys: terminal.usesApplicationCursorKeys,
                usesApplicationKeypad: terminal.usesApplicationKeypad && !isNumLockOn,
                isAlternateScreenActive: terminal.isAlternateScreenActive))
    }

    func scrollToBottom() {
        scroll(CGPoint(x: 0, y: bounds.maxY))
    }

    private func scrollsView(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard modifiers == .command || modifiers == [.command, .option] else {
            return false
        }
        return scrollView(for: event.specialKey, byLine: modifiers.contains(.option))
    }

    @discardableResult
    private func scrollView(for key: NSEvent.SpecialKey?, byLine: Bool = false) -> Bool {
        guard let clipView = superview as? NSClipView else {
            return false
        }
        let insets = clipView.contentInsets
        let height = clipView.bounds.height - insets.top - insets.bottom - Self.topPadding - Self.bottomPadding
        let page = CGFloat(max(Int(height / cellSize.height) - 1, 1)) * cellSize.height
        let step = byLine ? cellSize.height : page
        switch key {
        case .home where !byLine: scroll(CGPoint(x: 0, y: -insets.top))
        case .end where !byLine: scrollToBottom()
        case .pageUp: scroll(CGPoint(x: 0, y: clipView.bounds.minY - step))
        case .pageDown: scroll(CGPoint(x: 0, y: clipView.bounds.minY + step))
        default: return false
        }
        return true
    }

    override func doCommand(by selector: Selector) {
        guard let event = keyDownEvent else {
            return
        }
        if case .bytes(let bytes) = keyInput(event) {
            insertedText = ""
            session.send(bytes)
            keyDownEvent = nil
        }
    }

    func noteRevision() {
        guard accessibilityRevision != session.revision else {
            return
        }
        accessibilityRevision = session.revision
        scheduleAccessibilityNotification()
        textFinder?.noteClientStringWillChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        noteRevision()
        let terminal = session.terminal
        let colors = currentColors(for: terminal)
        colors.background.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.foreground]
        let graphemes = terminal.graphemes
        let lineCount = terminal.scrollback.count + terminal.rows
        let firstRow = max(
            Int((dirtyRect.minY - Self.topPadding) / cellSize.height) - 1,
            hidesScrollback ? terminal.scrollback.count : 0
        )
        let lastRow = min(Int((dirtyRect.maxY - Self.topPadding) / cellSize.height), lineCount - 1)
        let rows = firstRow ..< max(lastRow + 1, firstRow)
        var runs: [(Terminal.Line, Int, Range<Int>, Terminal.Style, NSColor, VisualOrder?, JoinedCells?)] = []
        for row in rows {
            let line = line(at: row, in: terminal)
            let order = Self.visualOrder(of: line, graphemes: graphemes)
            let joined = Self.joinedCells(in: line, graphemes: graphemes, order: order)
            let selected = selection?
                .columns(inLine: terminal.removedScrollbackCount + row, count: max(line.count, terminal.columns))
            var pixels = [UInt32](repeating: 0, count: line.count)
            for (columns, style) in Self.runs(in: line) {
                let (foreground, background) = colors.colors(for: style)
                let fill = background.map(Self.pixel) ?? 0
                if let background, fill == 0 {
                    background.setFill()
                    for rect in rects(row: row, columns: columns, order: order) {
                        backingAlignedRect(rect, options: .alignAllEdgesNearest).fill()
                    }
                }
                var hasInk = style.isUnderlined
                for column in columns {
                    hasInk = hasInk || !line[column].isSpace
                    let visual = order?.columns[column] ?? column
                    pixels[visual] = fill
                }
                if hasInk {
                    runs.append((line, row, columns, style, foreground, order, joined))
                }
            }
            let frame = rect(row: row, columns: 0 ..< line.count)
            let aligned = backingAlignedRect(frame, options: .alignAllEdgesNearest)
            if pixels.contains(where: { $0 != 0 }), let context = NSGraphicsContext.current?.cgContext,
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let provider = CGDataProvider(data: Data(bytes: pixels, count: 4 * pixels.count) as CFData),
                let image = CGImage(
                    width: line.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * line.count,
                    space: space, bitmapInfo: CGBitmapInfo(alpha: .premultipliedFirst, byteOrder: .order32Little),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            {
                context.saveGState()
                context.interpolationQuality = .none
                context.setShouldAntialias(false)
                context.clip(to: aligned)
                context.draw(
                    image, in: CGRect(x: frame.minX, y: aligned.minY, width: frame.width, height: aligned.height))
                context.restoreGState()
            }
            if let selected {
                (isFocused ? colors.selection : .unemphasizedSelectedTextBackgroundColor).setFill()
                for rect in rects(row: row, columns: selected, order: order) {
                    backingAlignedRect(rect, options: .alignAllEdgesNearest).fill()
                }
            }
        }
        for (line, row, columns, style, foreground, order, joined) in runs {
            drawText(
                line, columns: columns, row: row, style: style, foreground: foreground, graphemes: graphemes,
                order: order, joined: joined)
        }

        if hoveredLinkRevision != session.revision {
            updateHoveredLink()
        }
        if let hoveredLink {
            colors.foreground.setFill()
            for span in hoveredLink.spans {
                for rect in rects(row: span.row, columns: span.columns, order: visualOrder(ofRow: span.row)) {
                    CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
                }
            }
        }

        let cursor = cursorRect
        guard markedText.isEmpty else {
            let text = NSMutableAttributedString(string: markedText, attributes: attributes)
            let range = NSRange(location: 0, length: text.length)
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            markedString.enumerateAttribute(.underlineStyle, in: range) {
                style, range, _ in
                if let style {
                    text.addAttribute(.underlineStyle, value: style, range: range)
                }
            }
            let size = text.size()
            let origin = CGPoint(
                x: max(Self.padding, min(cursor.minX, bounds.width - Self.padding - size.width)),
                y: cursor.minY
            )
            colors.background.setFill()
            CGRect(origin: origin, size: CGSize(width: size.width, height: max(size.height, cursor.height)))
                .fill(using: .copy)
            text.draw(at: origin)
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
        let order = Self.visualOrder(of: line, graphemes: graphemes)
        let joined = Self.joinedCells(in: line, graphemes: graphemes, order: order)
        let columns = joined?.expanded(cursorColumns) ?? cursorColumns
        var style = line[columns.lowerBound].style
        style.isUnderlined = line[cursorColumns.lowerBound].style.isUnderlined
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if columns != cursorColumns {
            NSBezierPath(rect: cursor).setClip()
        }
        drawText(
            line,
            columns: columns,
            row: terminal.scrollback.count + terminal.cursor.row,
            style: style,
            foreground: colors.colors(for: style).foreground,
            graphemes: graphemes,
            order: order,
            joined: joined
        )
    }

    private static func cellSize(of font: NSFont) -> CGSize {
        guard font != defaultFont else {
            return CGSize(width: 7, height: 15)
        }
        return CGSize(
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

    func drawText(
        _ line: Terminal.Line,
        columns: Range<Int>,
        row: Int,
        style: Terminal.Style,
        foreground: NSColor,
        graphemes: Terminal.Graphemes,
        order: VisualOrder?,
        joined: JoinedCells?
    ) {
        guard !style.isHidden, let context = NSGraphicsContext.current?.cgContext
        else {
            return
        }
        let font = fonts.font(for: style)
        let index = fonts.index(for: style)
        let color = style.isFaint ? foreground.withAlphaComponent(0.42) : foreground
        let top = Self.topPadding + CGFloat(row) * cellSize.height
        let baseline = top + font.ascender
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        defer { context.textMatrix = .identity }
        var batchFont: CTFont?
        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
        func flush() {
            if let batchFont, !glyphs.isEmpty {
                CTFontDrawGlyphs(batchFont, glyphs, positions, glyphs.count, context)
            }
            glyphs.removeAll(keepingCapacity: true)
            positions.removeAll(keepingCapacity: true)
        }
        for column in columns where !line[column].isSpace {
            if joined?.headsOfFollowers[column] != nil {
                continue
            }
            let character = joined?.heads[column]?.text ?? graphemes.character(of: line[column])
            let visual = order?.columns[column] ?? column
            let x = Self.padding + CGFloat(visual) * cellSize.width
            let cell = CGRect(origin: CGPoint(x: x, y: top), size: cellSize)
            if Self.drawsSeparator(character, in: cell, context: context) {
                continue
            }
            let entry = fonts.glyphs.entry(
                for: character, font: font, index: index, isMirrored: order?.isReversed[column] == true)
            for run in entry.runs {
                if let current = batchFont, !CFEqual(current, run.font) {
                    flush()
                }
                batchFont = run.font
                glyphs += run.glyphs
                positions += run.positions.map { CGPoint(x: x + $0.x, y: $0.y - baseline) }
            }
        }
        flush()
        let thickness = max(font.underlineThickness, 1)
        let spans = rects(row: row, columns: columns, order: order)
        if style.isUnderlined {
            context.fill(
                spans.map {
                    backingAlignedRect(
                        CGRect(x: $0.minX, y: top + cellSize.height - thickness, width: $0.width, height: thickness),
                        options: .alignAllEdgesNearest)
                })
        }
    }

    private static func pixel(_ color: NSColor) -> UInt32 {
        guard color.type == .componentBased, color.colorSpace == .sRGB else {
            return 0
        }
        return [1, color.redComponent, color.greenComponent, color.blueComponent]
            .reduce(0) { $0 << 8 | UInt32((min(max($1, 0), 1) * color.alphaComponent * 255).rounded()) }
    }

    var cursorRect: CGRect {
        let row = session.terminal.scrollback.count + session.terminal.cursor.row
        return rects(row: row, columns: cursorColumns, order: visualOrder(ofRow: row))[0]
    }

    private var cursorColumns: Range<Int> {
        let cursor = session.terminal.cursor
        let width = Int(session.terminal.screen[cursor.row][cursor.column].width)
        if width == 0, cursor.column > 0 {
            return cursor.column - 1 ..< cursor.column + 1
        }
        return cursor.column ..< cursor.column + max(width, 1)
    }

    func fit(to size: CGSize) {
        let columns = (size.width - 2 * Self.padding) / cellSize.width
        let rows = (size.height - Self.topPadding - Self.bottomPadding) / cellSize.height
        let canSize = columns >= CGFloat(Self.minimumColumns) && rows >= CGFloat(Self.minimumRows)
        if canSize, session.sizingView == nil {
            session.sizingView = self
        }
        if canSize, session.sizingView === self {
            session.resize(
                columns: Int(min(columns, CGFloat(Self.maximumColumns))),
                rows: Int(min(rows, CGFloat(Self.maximumRows))),
                cellSize: cellSize
            )
        }
        if session.terminal.columns != fittedColumns {
            selection = nil
            fittedColumns = session.terminal.columns
        }
        let lineCount = session.terminal.scrollback.count + session.terminal.rows
        let height = CGFloat(lineCount) * cellSize.height + Self.topPadding + Self.bottomPadding
        let screenHeight = CGFloat(session.terminal.rows) * cellSize.height + Self.topPadding + Self.bottomPadding
        setFrameSize(CGSize(width: size.width, height: max(size.height, height + max(size.height - screenHeight, 0))))
    }

    func rect(row: Int, columns: Range<Int>) -> CGRect {
        CGRect(
            x: Self.padding + CGFloat(columns.lowerBound) * cellSize.width,
            y: Self.topPadding + CGFloat(row) * cellSize.height,
            width: CGFloat(columns.count) * cellSize.width,
            height: cellSize.height
        )
    }
}
