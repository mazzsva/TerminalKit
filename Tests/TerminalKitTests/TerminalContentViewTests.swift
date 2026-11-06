import AppKit
import Foundation
import SwiftUI
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalContentViewTests {
    @Test func fitsTheScreenToTheView() {
        let session = TerminalSession(running: "exit")
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 20 + view.cellSize.width * 100.5, height: 17 + view.cellSize.height * 30.5))
        #expect(session.terminal.columns == 100)
        #expect(session.terminal.rows == 30)
    }

    @Test func keepsTheSizeInAViewThatIsTooSmall() {
        let session = TerminalSession(running: "exit")
        let view = TerminalContentView(session: session)
        for size in [CGSize.zero, cells(9.9, 30, in: view), cells(100.5, 1.9, in: view)] {
            view.fit(to: size)
            #expect(session.terminal.columns == 80)
            #expect(session.terminal.rows == 24)
            #expect(session.sizingView == nil)
        }
        view.fit(to: cells(10.5, 2.5, in: view))
        #expect(session.terminal.columns == 10)
        #expect(session.terminal.rows == 2)
    }

    @Test func limitsTheSize() {
        let session = TerminalSession(running: "exit")
        let view = TerminalContentView(session: session)
        view.fit(to: cells(5_000, 3_000, in: view))
        #expect(session.terminal.columns == 1_000)
        #expect(session.terminal.rows == 1_000)
        view.font = .monospacedSystemFont(ofSize: .infinity, weight: .regular)
        view.fit(to: CGSize(width: 400, height: 300))
        #expect(session.terminal.columns == 1_000)
    }

    @Test func letsTheLastViewThatJoinsAWindowSizeTheSession() {
        let session = TerminalSession(running: "exit")
        let first = TerminalContentView(session: session)
        let second = TerminalContentView(session: session)
        let windows = [KeyWindow(contentView: first), KeyWindow(contentView: second)]
        windows[1].isKey = false
        windows[0].isKey = false
        windows[0].isKey = true
        first.fit(to: cells(100.5, 30.5, in: first))
        second.fit(to: cells(60.5, 20.5, in: second))
        #expect(session.terminal.columns == 60)
    }

    @Test func keepsTheScrollbackWhenTheViewCollapses() async throws {
        let session = TerminalSession(running: "seq -f 'line %g abcdefghijklmnopqrstuvwxyz' 1 2000")
        let view = TerminalContentView(session: session)
        view.fit(to: cells(100.5, 30.5, in: view))
        try session.start()
        await session.waitForExit()
        view.fit(to: .zero)
        view.fit(to: cells(100.5, 30.5, in: view))
        #expect(session.terminal.removedScrollbackCount == 0)
        #expect(session.terminal.scrollback.count == 2000 - 29)
    }

    private func cells(_ columns: CGFloat, _ rows: CGFloat, in view: TerminalContentView) -> CGSize {
        CGSize(width: 20 + view.cellSize.width * columns, height: 17 + view.cellSize.height * rows)
    }

    @Test func makesTheStyledFontsFromTheFont() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        view.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        #expect(view.fonts.bold.pointSize == 20)
        #expect(view.fonts.bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(view.fonts.boldItalic.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
    }

    @Test func drawsTheScreen() async throws {
        let session = TerminalSession(running: "printf 'hello\\r'")
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let blankImage = try image(of: view)

        try session.start()
        await session.waitForExit()
        #expect(try image(of: view) != blankImage)
    }

    @Test func drawsTheCursor() throws {
        let session = TerminalSession(running: "exit")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        let corner = CGPoint(x: 190, y: 90)
        #expect(color(in: representation, at: center) != color(in: representation, at: corner))
        #expect(window.firstResponder === view)
    }

    @Test func drawsAnUnderlineCursor() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[4 q'")
        let rect = view.cursorRect
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.maxY - 1)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.maxY - 3)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.midY)), to: background))
        #expect(window.firstResponder === view)
    }

    @Test func drawsABarCursor() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[6 q'")
        let rect = view.cursorRect
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.minX + 1, y: rect.midY)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.minX + 3, y: rect.midY)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.midY)), to: background))
        #expect(window.firstResponder === view)
    }

    @Test(arguments: [("4", CGRect(x: 0, y: 0, width: 0, height: 3)), ("6", CGRect(x: 3, y: 0, width: 0, height: 0))])
    func drawsTheTextUnderAThinCursor(shape: String, inset: CGRect) async throws {
        let (thin, thinWindow) = try await focusedView(running: "printf 'X\\b\\033[\(shape) q'")
        let (hidden, hiddenWindow) = try await focusedView(running: "printf 'X\\b\\033[?25l'")
        let rect = CGRect(
            x: thin.cursorRect.minX + inset.minX,
            y: thin.cursorRect.minY,
            width: thin.cursorRect.width - inset.minX,
            height: thin.cursorRect.height - inset.height
        )
        #expect(try pixels(in: rect, of: thin) == pixels(in: rect, of: hidden))
        #expect(try Set(pixels(in: rect, of: thin).map { $0?.description }).count > 1)
        #expect(thinWindow.firstResponder === thin && hiddenWindow.firstResponder === hidden)
    }

    @Test(arguments: ["4", "6"])
    func drawsAHollowCursorOfEachShapeWithoutTheFocus(shape: String) async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[\(shape) q'")
        window.isKey = false
        let rect = view.cursorRect
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.maxX - 0.5, y: rect.midY)), to: background))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.minY + 0.5)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.midY)), to: background))
    }

    @Test func drawsAHollowCursorWithoutTheFocus() async throws {
        let (view, window) = try await focusedView(running: "exit")
        let edge = CGPoint(x: view.cursorRect.minX + 0.5, y: view.cursorRect.midY)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let corner = CGPoint(x: 190, y: 90)
        let focused = try representation(of: view)
        let cursor = color(in: focused, at: center)
        #expect(!isClose(cursor, to: color(in: focused, at: corner)))

        window.isKey = false
        let unfocused = try representation(of: view)
        #expect(isClose(color(in: unfocused, at: edge), to: cursor))
        #expect(isClose(color(in: unfocused, at: center), to: color(in: unfocused, at: corner)))

        window.isKey = true
        #expect(isClose(color(in: try representation(of: view), at: center), to: cursor))
    }

    @Test func drawsAHollowCursorWhenAnotherViewHasTheFocus() async throws {
        let (view, window) = try await focusedView(running: "exit")
        let textView = NSTextView()
        view.addSubview(textView)
        window.makeFirstResponder(textView)
        let representation = try representation(of: view)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let corner = CGPoint(x: 190, y: 90)
        #expect(isClose(color(in: representation, at: center), to: color(in: representation, at: corner)))
        #expect(!view.isFocused)

        window.makeFirstResponder(view)
        #expect(view.isFocused)
    }

    @Test func losesTheFocusWhenItLeavesTheWindow() async throws {
        let (view, window) = try await focusedView(running: "exit")
        let container = NSView()
        window.contentView = container
        #expect(!view.isFocused)

        container.addSubview(view)
        #expect(view.isFocused)
    }

    @Test func reportsTheFocusWhenTheProcessAsks() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[?1004h'; dd bs=1 count=6 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        window.isKey = false
        try session.start()
        for await isEnabled in Observations({ session.terminal.usesFocusReporting }) where isEnabled {
            break
        }
        window.isKey = true
        window.isKey = true
        window.isKey = false
        #expect(await session.linesAfterExit().contains("1b  5b  49  1b  5b  4f"))
    }

    @Test func reportsNoFocusWhenTheProcessDoesNotAsk() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        try session.start()
        await session.waitForText("ready")
        window.isKey = false
        window.isKey = true
        view.keyDown(with: try keyDown("a"))
        #expect(await session.linesAfterExit().contains("61"))
    }

    @Test(arguments: [TerminalPalette.standard.background, .clear], [1, 2] as [CGFloat])
    func drawsTheCharacterUnderTheCursor(background: Color, scale: CGFloat) async throws {
        let character = try await drawnView(running: "printf 'X\\b'")
        let space = try await drawnView(running: "printf ' \\b'")
        var palette = TerminalPalette.standard
        palette.background = background
        palette.cursor = .red
        let windows = [ScaledKeyWindow(contentView: character), ScaledKeyWindow(contentView: space)]
        for (window, view) in zip(windows, [character, space]) {
            window.scale = scale
            view.palette = palette
        }
        #expect(try pixels(in: character.cursorRect, of: character) != pixels(in: space.cursorRect, of: space))
        #expect(windows[0].firstResponder === character && windows[1].firstResponder === space)
    }

    @Test(arguments: [("中\\b\\b", 0), ("中\\b", 0), ("%78s中", 78)])
    func coversAWideCharacterWithTheCursor(text: String, column: Int) async throws {
        let view = try await drawnView(running: "printf '\(text)'")
        #expect(view.cursorRect == view.rect(row: 0, columns: column ..< column + 2))
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func drawsTheWideCharacterUnderTheCursor(scale: CGFloat) async throws {
        let view = try await drawnView(running: "printf '中\\b'")
        let window = ScaledKeyWindow(contentView: view)
        window.scale = scale
        view.palette.cursor = .red
        for column in 0 ..< 2 {
            let cell = view.rect(row: 0, columns: column ..< column + 1).insetBy(dx: 1, dy: 1)
            let pixels = try pixels(in: cell, of: view).map { try #require($0?.usingColorSpace(.sRGB)) }
            #expect(pixels.contains { $0.redComponent - $0.greenComponent > 0.3 })
            #expect(pixels.contains { $0.redComponent - $0.greenComponent < 0.3 })
        }
        #expect(window.firstResponder === view)
    }

    @Test func hidesTheCursor() async throws {
        let view = try await drawnView(running: "printf '\\033[?25l'")
        let representation = try representation(of: view)
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        #expect(color(in: representation, at: center) == color(in: representation, at: CGPoint(x: 190, y: 90)))
    }

    @Test func drawsTheTextAfterAWideCharacterInItsCell() async throws {
        let wide = try await drawnView(running: "printf '中x\\n'")
        let narrow = try await drawnView(running: "printf '  x\\n'")
        let cell = CGRect(
            x: 10 + 2 * wide.cellSize.width,
            y: 7,
            width: wide.cellSize.width,
            height: wide.cellSize.height
        )
        #expect(try pixels(in: cell, of: wide) == pixels(in: cell, of: narrow))
    }

    @Test func drawsRightToLeftTextFromRightToLeft() async throws {
        let word = try await drawnView(running: "printf '\\327\\220\\327\\221\\n'")
        let second = try await drawnView(running: "printf '\\327\\221\\n'")
        let first = try await drawnView(running: "printf ' \\327\\220\\n'")
        let cell = CGRect(x: 10, y: 7, width: word.cellSize.width, height: word.cellSize.height)
        let next = cell.offsetBy(dx: word.cellSize.width, dy: 0)
        #expect(try pixels(in: cell, of: word) == pixels(in: cell, of: second))
        #expect(try pixels(in: next, of: word) == pixels(in: next, of: first))
        #expect(try pixels(in: cell, of: word) != pixels(in: next, of: word))
    }

    @Test func drawsTheMirroredGlyphInRightToLeftText() async throws {
        let word = try await drawnView(running: "printf '\\327\\220(\\327\\221)\\n'")
        let open = try await drawnView(running: "printf '(\\n'")
        let cell = CGRect(x: 10, y: 7, width: word.cellSize.width, height: word.cellSize.height)
        #expect(try pixels(in: cell, of: word) == pixels(in: cell, of: open))
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func underlinesTheVisualCellsOfRightToLeftText(scale: CGFloat) async throws {
        let plain = try await drawnView(running: "printf '\\327\\220\\327\\221\\n'")
        let view = try await drawnView(running: "printf '\\033[4m\\327\\220\\033[m\\327\\221\\n'")
        let windows = [ScaledWindow(contentView: plain), ScaledWindow(contentView: view)]
        for window in windows {
            window.scale = scale
        }
        let font = view.fonts.regular
        let underline = CGRect(
            x: 10, y: 7 + font.ascender - font.underlinePosition, width: view.cellSize.width,
            height: max(font.underlineThickness, 1)
        )
        .insetBy(dx: 0, dy: -1)
        let next = underline.offsetBy(dx: view.cellSize.width, dy: 0)
        #expect(try pixels(in: underline, of: view) == pixels(in: underline, of: plain))
        #expect(try pixels(in: next, of: view) != pixels(in: next, of: plain))
    }

    @Test(arguments: ["41", "48;2;0;200;0"])
    func drawsTheBackgroundColorInTheVisualCellsOfRightToLeftText(parameters: String) async throws {
        let plain = try await drawnView(running: "printf '\\327\\220\\327\\221\\n'")
        let view = try await drawnView(running: "printf '\\033[\(parameters)m\\327\\220\\033[m\\327\\221\\n'")
        let cell = CGRect(x: 10, y: 7, width: view.cellSize.width, height: 2)
        let next = cell.offsetBy(dx: view.cellSize.width, dy: 0)
        #expect(try pixels(in: cell, of: view) == pixels(in: cell, of: plain))
        #expect(try pixels(in: next, of: view) != pixels(in: next, of: plain))
    }

    @Test func drawsTheCharacterUnderTheCursorInItsVisualCell() async throws {
        let view = try await drawnView(running: "printf '\\327\\220\\327\\221\\r'")
        let reference = try await drawnView(running: "printf ' \\327\\220\\b'")
        let windows = [ScaledKeyWindow(contentView: view), ScaledKeyWindow(contentView: reference)]
        view.palette.cursor = .red
        reference.palette.cursor = .red
        #expect(view.cursorRect == reference.cursorRect)
        #expect(try pixels(in: view.cursorRect, of: view) == pixels(in: reference.cursorRect, of: reference))
        #expect(windows[0].firstResponder === view && windows[1].firstResponder === reference)
    }

    @Test(arguments: ["\\341\\200\\270", "\\340\\244\\276"])
    func drawsASpacingMarkAlone(character: String) async throws {
        let mark = try await drawnView(running: "printf '\(character)x\\n'")
        let spaced = try await drawnView(running: "printf ' x\\n'")
        let first = CGRect(x: 10, y: 7, width: mark.cellSize.width, height: mark.cellSize.height)
        #expect(try pixels(in: first, of: mark) != pixels(in: first, of: spaced))
    }

    @Test func drawsABlockFromTheFont() throws {
        let entry = GlyphCache().entry(for: "\u{2588}", font: TerminalContentView.defaultFont, index: 0)
        #expect(entry.runs.flatMap(\.glyphs).count == 1)
    }

    @Test func drawsEachCharacterInItsCellWithAProportionalFont() async throws {
        let narrow = try await drawnView(running: "printf 'iiiiW\\n'")
        let spaced = try await drawnView(running: "printf '    W\\n'")
        for view in [narrow, spaced] {
            view.font = .systemFont(ofSize: 13)
        }
        let cell = CGRect(
            x: 10 + 4 * narrow.cellSize.width,
            y: 7,
            width: narrow.cellSize.width,
            height: narrow.cellSize.height
        )
        #expect(try pixels(in: cell, of: narrow) == pixels(in: cell, of: spaced))
    }

    @Test(arguments: ["e\\314\\201", "\\360\\237\\230\\200", "\\344\\270\\255", "\\320\\226"])
    func drawsACharacterOutsideASCII(character: String) async throws {
        let blank = try await drawnView(running: "printf '  \\r'")
        let drawn = try await drawnView(running: "printf '\(character)\\r'")
        let cells = CGRect(x: 10, y: 7, width: 2 * drawn.cellSize.width, height: drawn.cellSize.height)
        #expect(try pixels(in: cells, of: drawn) != pixels(in: cells, of: blank))
    }

    @Test(arguments: [
        ("\\344\\270\\255", "\\346\\226\\207"), ("\\360\\237\\230\\200", "\\360\\237\\232\\200"),
    ])
    func drawsTheGlyphsOfTheFallbackFont(character: String, other: String) async throws {
        let first = try await drawnView(running: "printf 'x\(character)\\r'")
        let second = try await drawnView(running: "printf 'x\(other)\\r'")
        let spaced = try await drawnView(running: "printf ' \(character)\\r'")
        let cells = CGRect(
            x: 10 + first.cellSize.width, y: 7, width: 2 * first.cellSize.width, height: first.cellSize.height)
        #expect(try pixels(in: cells, of: first) != pixels(in: cells, of: second))
        #expect(try pixels(in: cells, of: first) == pixels(in: cells, of: spaced))
    }

    @Test(
        arguments: [("\u{585A}", "\u{FA10}"), ("\u{03B1}\u{0301}", "\u{1F71}"), ("\u{1F44D}", "\u{1F44D}\u{1F3FD}")]
            as [(String, String)])
    func keysTheGlyphsByTheExactScalarsOfACharacter(drawn: String, character: String) {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let cache = GlyphCache()
        _ = cache.entry(for: drawn, font: font, index: 0)
        let glyphs = cache.entry(for: character, font: font, index: 0).runs.map(\.glyphs)
        #expect(glyphs == GlyphCache().entry(for: character, font: font, index: 0).runs.map(\.glyphs))
    }

    @Test(arguments: ["⏺", "⏸"], [1, 2] as [CGFloat])
    func drawsTheGlyphsOfTheFallbackFontOnTheBaseline(character: String, scale: CGFloat) async throws {
        let view = try await drawnView(running: "printf 'a \(character)\\n'")
        let window = ScaledWindow(contentView: view)
        window.scale = scale
        let font = view.fonts.regular
        let representation = try representation(of: view)
        #expect(CGFloat(representation.pixelsWide) == scale * view.bounds.width)
        let background = try #require(color(in: representation, at: CGPoint(x: 190, y: 90))?.usingColorSpace(.sRGB))
        for (column, glyph) in [(0, "a"), (2, character)] {
            let run = try #require(view.fonts.glyphs.entry(for: glyph, font: font, index: 0).runs.first)
            let bounds = CTFontGetBoundingRectsForGlyphs(run.font, .default, run.glyphs, nil, 1)
            let x = 10 + CGFloat(column) * view.cellSize.width
            let top = stride(from: 7, to: 7 + view.cellSize.height, by: 1 / scale)
                .first { y in
                    stride(from: x, to: x + view.cellSize.width, by: 1 / scale)
                        .contains {
                            let pixel = color(in: representation, at: CGPoint(x: $0, y: y))?.usingColorSpace(.sRGB)
                            return abs((pixel?.brightnessComponent ?? 0) - background.brightnessComponent) > 0.5
                        }
                }
            #expect(abs(try #require(top) - (7 + font.ascender - bounds.maxY)) < 1)
        }
    }

    @Test func underlinesARunWithAWideCharacter() async throws {
        let view = try await drawnView(running: "printf '\\033[4ma\\344\\270\\255b\\033[m\\r'")
        let font = view.fonts.regular
        let y = 7 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        let underline = stride(from: 10 + view.cellSize.width / 4, to: 10 + view.cellSize.width * 3.75, by: 1)
            .map { color(in: representation, at: CGPoint(x: $0, y: y)) }
        #expect(underline.allSatisfy { $0 != background })
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func drawsTheUnderlineColorAsAPlainUnderline(scale: CGFloat) async throws {
        let plain = try await drawnView(running: "printf '\\033[4mab\\033[m\\r'")
        let view = try await drawnView(running: "printf '\\033[4;58:2::0:200:0mab\\033[m\\r'")
        let windows = [ScaledWindow(contentView: plain), ScaledWindow(contentView: view)]
        for window in windows {
            window.scale = scale
        }
        let cells = CGRect(x: 10, y: 7, width: 2 * view.cellSize.width, height: view.cellSize.height)
        #expect(try pixels(in: cells, of: view) == pixels(in: cells, of: plain))
    }

    @Test(arguments: ["", "7;"], [1, 2] as [CGFloat])
    func drawsTheUnderlineInTheTextColor(parameters: String, scale: CGFloat) async throws {
        let view = try await drawnView(running: "printf '\\033[?25l\\033[\(parameters)4;31mab\\033[m\\r'")
        let window = ScaledWindow(contentView: view)
        window.scale = scale
        view.palette = highContrastPalette
        let font = view.fonts.regular
        let y = 7 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representation = try representation(of: view)
        let underline = try stride(from: 10, to: 9 + 2 * view.cellSize.width, by: 1 / scale)
            .map { try #require(color(in: representation, at: CGPoint(x: $0, y: y))?.usingColorSpace(.sRGB)) }
        #expect(
            underline.allSatisfy {
                ($0.redComponent - max($0.greenComponent, $0.blueComponent) > 0.1) == parameters.isEmpty
            })
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func alignsTheUnderlineToThePixels(scale: CGFloat) async throws {
        let view = try await drawnView(running: "printf '\\033[4;31m  \\033[;31m█\\n'")
        let window = ScaledWindow(contentView: view)
        window.scale = scale
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        let foreground = color(in: representation, at: CGPoint(x: 10 + 2.5 * view.cellSize.width, y: 10))
        let column = CGRect(x: 10 + view.cellSize.width, y: 7, width: 1 / scale, height: view.cellSize.height)
        let pixels = try pixels(in: column, of: view)
        #expect(pixels.count { isClose($0, to: foreground) } == Int(scale))
        #expect(pixels.allSatisfy { isClose($0, to: foreground) || isClose($0, to: background) })
    }

    @Test func drawsTheUnderlineUnderTheCursorInTheTextColor() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[4;32mX\\033[m\\b'")
        let font = view.fonts.regular
        let y = 7 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representation = try representation(of: view)
        let underline = try stride(from: view.cursorRect.minX, to: view.cursorRect.maxX, by: 1)
            .map { try #require(color(in: representation, at: CGPoint(x: $0, y: y))?.usingColorSpace(.sRGB)) }
        #expect(underline.contains { $0.greenComponent - max($0.redComponent, $0.blueComponent) > 0.1 })
        #expect(window.firstResponder === view)
    }

    @Test func drawsFaintTextAtTheMeasuredAlpha() async throws {
        let view = try await drawnView(running: "printf '\\033[?25l\\033[2;4mab\\033[m\\r'")
        view.palette = highContrastPalette
        let font = view.fonts.regular
        let y = 7 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representation = try representation(of: view)
        let color = try #require(color(in: representation, at: CGPoint(x: 14, y: y))?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 0.58) < 0.25)
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func drawsAFaintUnderline(scale: CGFloat) async throws {
        let plain = try await drawnView(running: "printf '\\033[?25l\\033[4mab\\033[m\\r'")
        let view = try await drawnView(running: "printf '\\033[?25l\\033[2;4mab\\033[m\\r'")
        let windows = [ScaledWindow(contentView: plain), ScaledWindow(contentView: view)]
        for window in windows {
            window.scale = scale
            (window.contentView as? TerminalContentView)?.palette = highContrastPalette
        }
        let font = view.fonts.regular
        let y = 7 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representations = try [representation(of: plain), representation(of: view)]
        for x in stride(from: 10, to: 9 + 2 * view.cellSize.width, by: 1 / scale) {
            let point = CGPoint(x: x, y: y)
            #expect(color(in: representations[0], at: point) != color(in: representations[1], at: point))
        }
    }

    @Test func drawsTheBackgroundColor() async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[m'")
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 180 / 255) < 0.02)
        #expect(abs(color.greenComponent - 85 / 255) < 0.02)
        #expect(abs(color.blueComponent - 71 / 255) < 0.02)
    }

    @Test func drawsTheBackgroundColorWithoutASeamBetweenRuns() async throws {
        let view = try await drawnView(running: "printf '\\033[44m        \\033[31m        \\033[m'")
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        #expect(view.cellSize.width != view.cellSize.width.rounded())
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        let fill = color(in: try representation(of: view), at: center)
        let edge = CGRect(x: 10 + view.cellSize.width * 8 - 2, y: center.y, width: 4, height: 1)
        #expect(try pixels(in: edge, of: view).allSatisfy { isClose($0, to: fill) })
    }

    @Test(arguments: ["\u{200D}", "\u{FEFF}", "\u{E0061}"])
    func drawsNoBlockForAnIgnorableCharacter(character: String) async throws {
        let view = try await drawnView(running: "printf 'a\(character)b\\n'")
        let representation = try representation(of: view)
        let empty = color(in: representation, at: CGPoint(x: 190, y: 90))
        let center = CGPoint(x: 10 + view.cellSize.width * 1.5, y: 7 + view.cellSize.height / 2)
        #expect(isClose(color(in: representation, at: center), to: empty))
    }

    @Test func drawsTheSelectionWithThePaletteColor() throws {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        let window = KeyWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let green = Color(.sRGB, red: 0.4, green: 0.6, blue: 0.2)
        let center = CGPoint(x: 10 + view.cellSize.width * 2.5, y: 7 + view.cellSize.height / 2)
        view.palette.background = green
        let fill = color(in: try representation(of: view), at: center)
        view.palette = .standard
        view.palette.selection = green
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 8))
        #expect(window.firstResponder === view)
        #expect(isClose(color(in: try representation(of: view), at: center), to: fill))
    }

    @Test func drawsTheSelectionWithoutASeamAtItsEdge() async throws {
        let view = try await drawnView(running: "printf '        \\033[44m        \\033[m'")
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 8))
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        let representation = try representation(of: view)
        let selected = color(in: representation, at: center)
        let fill = color(in: representation, at: CGPoint(x: center.x + view.cellSize.width * 12, y: center.y))
        let edge = CGRect(x: 10 + view.cellSize.width * 8 - 2, y: center.y, width: 4, height: 1)
        #expect(!isClose(selected, to: fill))
        #expect(try pixels(in: edge, of: view).allSatisfy { isClose($0, to: selected) || isClose($0, to: fill) })
    }

    @Test(arguments: [false, true], [1, 2] as [CGFloat])
    func drawsAVerticalLineWithoutASeamBetweenRows(isSelected: Bool, scale: CGFloat) async throws {
        let view = try await drawnView(
            running: isSelected ? "printf '│\\r\\n│\\n'" : "printf '\\033[44m│\\r\\n│\\033[m\\n'")
        let window = ScaledWindow(contentView: view)
        window.scale = scale
        view.palette = highContrastPalette
        if isSelected {
            view.selection = TerminalContentView.Selection(
                anchor: .init(line: 0, column: 0), head: .init(line: 1, column: 1))
        }
        let strip = CGRect(x: 0, y: 7 + view.cellSize.height, width: view.bounds.width, height: view.cellSize.height)
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: strip))
        view.cacheDisplay(in: strip, to: representation)
        let background = try #require(
            color(in: representation, at: CGPoint(x: 10, y: view.cellSize.height / 2))?.usingColorSpace(.sRGB))
        func ink(y: CGFloat) -> CGFloat {
            stride(from: 10 + view.cellSize.width / 4, to: 10 + view.cellSize.width * 3 / 4, by: 1 / scale)
                .compactMap { color(in: representation, at: CGPoint(x: $0, y: y))?.usingColorSpace(.sRGB) }
                .map { abs($0.brightnessComponent - background.brightnessComponent) }
                .max() ?? 0
        }
        #expect(ink(y: 0) >= ink(y: view.cellSize.height / 2))
        #expect(ink(y: view.cellSize.height / 2) > 0.15)
    }

    @Test(arguments: [1, 2] as [CGFloat], [0, 0.25] as [CGFloat])
    func drawsTruecolorCellsAsOneFillPerCell(scale: CGFloat, offset: CGFloat) async throws {
        let colors: [[Int]] = (0 ..< 48).map { index in [37, 91, 53, 29, 67, 13].map { index * $0 % 256 } }
        let text: [String] = colors.indices.map { index in
            let color = colors[index]
            let style = "\\033[\(index % 5 == 0 ? 7 : 27);38;2;\(color[0]);\(color[1]);\(color[2]);48;2;"
            let end = index % 12 == 11 ? "\\r\\n" : ""
            return style + "\(color[3]);\(color[4]);\(color[5])m \(end)"
        }
        let view = try await drawnView(running: "printf '\(text.joined())\\033[m\\033[?25l'")
        view.palette.background = .clear
        let reference = FillView(frame: view.frame)
        let containers = [NSView(), NSView()]
        for (container, subview) in zip(containers, [view, reference]) {
            let window = ScaledWindow(contentView: container)
            window.scale = scale
            container.addSubview(subview)
            subview.setFrameOrigin(CGPoint(x: offset / scale, y: offset / scale))
        }
        for (index, color) in colors.enumerated() {
            let components = color.map { CGFloat($0) / 255 }
            let foreground = NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
            let background = NSColor(srgbRed: components[3], green: components[4], blue: components[5], alpha: 1)
            let fill = index % 5 == 0 ? foreground : background
            let cell = view.backingAlignedRect(
                view.rect(row: index / 12, columns: index % 12 ..< index % 12 + 1), options: .alignAllEdgesNearest)
            reference.fills.append((cell, fill))
        }
        let (actual, expected) = (try representation(of: containers[0]), try representation(of: containers[1]))
        let grid = view.frame
        let height = containers[0].bounds.height
        let rows = Int(((height - grid.maxY) * scale).rounded()) ..< Int(((height - grid.minY) * scale).rounded())
        let columns = Int((grid.minX * scale).rounded()) ..< Int((grid.maxX * scale).rounded())
        #expect(
            rows.allSatisfy { y in
                columns.allSatisfy { isClose(actual.colorAt(x: $0, y: y), to: expected.colorAt(x: $0, y: y)) }
            })
    }

    @Test(arguments: ["\\033[41m  ", "\\033[31m██"], [1, 2] as [CGFloat])
    func drawsARowBelowTheTopOfTheDirtyRect(cells: String, scale: CGFloat) async throws {
        let session = TerminalSession(running: "seq 1 30; printf '\(cells)\\033[m'")
        let view = TerminalContentView(session: session)
        let window = ScaledWindow(contentView: NSView())
        window.scale = scale
        window.contentView?.addSubview(view)
        view.fit(to: CGSize(width: 200, height: 100))
        try session.start()
        await session.waitForExit()
        view.fit(to: CGSize(width: 200, height: 100))
        let row = session.terminal.scrollback.count + session.terminal.rows - 1
        let rect = view.rect(row: row - 2, columns: 0 ..< 1).union(view.rect(row: row, columns: 0 ..< 1))
        let part = try #require(view.bitmapImageRepForCachingDisplay(in: rect))
        view.cacheDisplay(in: rect, to: part)
        let center = CGPoint(x: rect.width / 2, y: rect.height - view.cellSize.height / 2)
        let full = try representation(of: view)
        let fill = color(in: full, at: CGPoint(x: rect.minX + center.x, y: rect.minY + center.y))
        #expect(isClose(color(in: part, at: center), to: fill))
        #expect(!isClose(fill, to: color(in: full, at: CGPoint(x: 190, y: rect.minY + center.y))))
    }

    @Test func fillsARowOfTruecolorCellsWithOneImage() async throws {
        let cells = (0 ..< 48).map { "\\033[38;2;\($0 * 5);0;0;48;2;0;\($0 * 5);0m\(["▀", "▄", "█", " "][$0 % 4])" }
        let view = try await drawnView(running: "printf '\(cells.joined())\\033[m\\r'")
        let counts = try operatorCounts(in: view.dataWithPDF(inside: view.bounds))
        #expect(counts.fills < 4)
        #expect(counts.images == 1)
    }

    @Test func drawsTheScrollback() async throws {
        let session = TerminalSession(running: "printf '\\033[41m  \\033[m'; seq 1 30")
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 200, height: 100))
        try session.start()
        await session.waitForExit()
        view.fit(to: CGSize(width: 200, height: 100))
        #expect(!session.terminal.scrollback.isEmpty)
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 180 / 255) < 0.02)
    }

    @Test func drawsWithThePalette() async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[m'")
        var palette = TerminalPalette.standard
        palette.background = Color(.sRGB, red: 0.2, green: 0.3, blue: 0.4)
        palette.ansiColors[1] = Color(.sRGB, red: 0.4, green: 0.6, blue: 0.2)
        view.palette = palette
        let representation = try representation(of: view)
        let cell = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        #expect(isClose(color(in: representation, at: cell), to: [0.4, 0.6, 0.2]))
        #expect(isClose(color(in: representation, at: CGPoint(x: 190, y: 90)), to: [0.2, 0.3, 0.4]))
    }

    @Test func makesAPaletteWithFewerANSIColors() {
        let palette = TerminalPalette(
            foreground: .white, background: .black, cursor: .gray, selection: .blue, ansiColors: [.red])
        #expect(palette.ansiColors == [.red])
    }

    @Test(arguments: [2, 20])
    func fillsTheANSIColorsFromTheStandardPalette(count: Int) async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[47m  \\033[107m  \\033[m'")
        var palette = TerminalPalette.standard
        palette.ansiColors =
            [.black, Color(.sRGB, red: 0.4, green: 0.6, blue: 0.2)]
            + Array(repeating: Color(.sRGB, red: 0.1, green: 0.9, blue: 0.5), count: count - 2)
        view.palette = palette
        let representation = try representation(of: view)
        let points = [0, 2, 4]
            .map { CGPoint(x: 10 + view.cellSize.width * (CGFloat($0) + 0.5), y: 7 + view.cellSize.height / 2) }
        let fill: [CGFloat] = count > 2 ? [0.1, 0.9, 0.5] : [222.0 / 255, 230.0 / 255, 236.0 / 255]
        let brightFill: [CGFloat] = count > 2 ? [0.1, 0.9, 0.5] : [230.0 / 255, 239.0 / 255, 246.0 / 255]
        #expect(isClose(color(in: representation, at: points[0]), to: [0.4, 0.6, 0.2]))
        #expect(isClose(color(in: representation, at: points[1]), to: fill))
        #expect(isClose(color(in: representation, at: points[2]), to: brightFill))
    }

    @Test func drawsTheForegroundColor() async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let red = try image(of: try await drawnView(running: "printf '\\033[31mX\\r'"))
        #expect(red != plain)
    }

    @Test(arguments: ["1", "2", "3", "4"])
    func drawsTheTextStyle(parameter: String) async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let styled = try image(of: try await drawnView(running: "printf '\\033[\(parameter)mX\\r'"))
        #expect(styled != plain)
    }

    @Test func drawsStrikethroughTextAsPlainText() async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let struck = try image(of: try await drawnView(running: "printf '\\033[9mX\\r'"))
        #expect(struck == plain)
    }

    @Test func drawsInverseText() async throws {
        let view = try await drawnView(running: "printf '\\033[7m  \\033[m'")
        let center = CGPoint(x: 10 + view.cellSize.width / 2, y: 7 + view.cellSize.height / 2)
        let representation = try representation(of: view)
        #expect(color(in: representation, at: center) != color(in: representation, at: CGPoint(x: 190, y: 90)))
    }

    @Test(arguments: ["\\033[7m", "\\033[?5h"], [1, 2] as [CGFloat])
    func drawsInverseTextOnAClearBackground(sequence: String, scale: CGFloat) async throws {
        let character = try await drawnView(running: "printf '\(sequence)X\\033[m\\r'")
        let space = try await drawnView(running: "printf '\(sequence) \\033[m\\r'")
        var palette = TerminalPalette.standard
        palette.foreground = .white
        palette.background = .clear
        let windows = [ScaledWindow(contentView: character), ScaledWindow(contentView: space)]
        for (window, view) in zip(windows, [character, space]) {
            window.scale = scale
            view.palette = palette
        }
        let cell = character.rect(row: 0, columns: 0 ..< 1)
        #expect(try pixels(in: cell, of: character) != pixels(in: cell, of: space))
    }

    @Test func drawsInReverseVideo() async throws {
        let view = try await drawnView(
            running:
                "printf '\\033[?5h\\033[41m \\033[0;7m \\033[0;40m \\033[0;47m \\033[0;107m \\033[m\u{2588}\\033[7m\u{2588}\\033[0;100m \\033[?25l'"
        )
        var palette = TerminalPalette.standard
        palette.foreground = Color(.sRGB, red: 0.2, green: 0.3, blue: 0.4)
        palette.background = Color(.sRGB, red: 0.6, green: 0.7, blue: 0.8)
        view.palette = palette
        view.setMarkedText(
            " \u{2588}",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let representation = try representation(of: view)
        let points = (0 ..< 10)
            .map { CGPoint(x: 10 + view.cellSize.width * (CGFloat($0) + 0.5), y: 7 + view.cellSize.height / 2) }
        #expect(isClose(color(in: representation, at: points[0]), to: [180.0 / 255, 85.0 / 255, 71.0 / 255]))
        #expect(isClose(color(in: representation, at: points[1]), to: [0.6, 0.7, 0.8]))
        #expect(isClose(color(in: representation, at: points[2]), to: [53.0 / 255, 66.0 / 255, 75.0 / 255]))
        #expect(isClose(color(in: representation, at: points[3]), to: [222.0 / 255, 230.0 / 255, 236.0 / 255]))
        #expect(isClose(color(in: representation, at: points[4]), to: [230.0 / 255, 239.0 / 255, 246.0 / 255]))
        #expect(isClose(color(in: representation, at: points[5]), to: [0.6, 0.7, 0.8]))
        #expect(isClose(color(in: representation, at: points[6]), to: [0.2, 0.3, 0.4]))
        #expect(isClose(color(in: representation, at: points[7]), to: [70.0 / 255, 92.0 / 255, 109.0 / 255]))
        #expect(isClose(color(in: representation, at: points[8]), to: [0.2, 0.3, 0.4]))
        #expect(isClose(color(in: representation, at: points[9]), to: [0.6, 0.7, 0.8]))
        #expect(isClose(color(in: representation, at: CGPoint(x: 190, y: 90)), to: [0.2, 0.3, 0.4]))
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func drawsTheCursorInReverseVideo(appearance: NSAppearance.Name) async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[?5h'")
        view.appearance = NSAppearance(named: appearance)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let edge = CGPoint(x: view.cursorRect.minX + 0.5, y: view.cursorRect.midY)
        let corner = CGPoint(x: 190, y: 90)
        let focused = try representation(of: view)
        #expect(!isClose(color(in: focused, at: center), to: color(in: focused, at: corner)))

        window.isKey = false
        let unfocused = try representation(of: view)
        #expect(!isClose(color(in: unfocused, at: edge), to: color(in: unfocused, at: corner)))
    }

    @Test func keepsTheCursorColorInReverseVideo() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[?5h'")
        view.palette.cursor = Color(.sRGB, red: 1, green: 0.5, blue: 0)
        let representation = try representation(of: view)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let drawn = try #require(color(in: representation, at: center)?.usingColorSpace(.sRGB))
        #expect(drawn.redComponent > 0.8 && drawn.blueComponent < 0.3)
        #expect(window.firstResponder === view)
    }

    @Test func drawsTheCursorInTheBackgroundColor() async throws {
        let (view, window) = try await focusedView(running: "exit")
        var palette = TerminalPalette.standard
        palette.cursor = palette.background
        view.palette = palette
        let representation = try representation(of: view)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let corner = CGPoint(x: 190, y: 90)
        #expect(isClose(color(in: representation, at: center), to: color(in: representation, at: corner)))
        #expect(window.firstResponder === view)
    }

    @Test func drawsTheTextUnderTheCursorInReverseVideo() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[?5h\u{2588}\u{2588}\\r'")
        let representation = try representation(of: view)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let cell = CGPoint(x: center.x + view.cellSize.width, y: center.y)
        #expect(isClose(color(in: representation, at: center), to: color(in: representation, at: cell)))
        #expect(window.firstResponder === view)
    }

    @Test func drawsTheTextUnderTheCursorOnAColorInReverseVideo() async throws {
        let (view, window) = try await focusedView(
            running: "printf '\\033[?5h\\033[30m\u{2588}\u{2588}\\033[m\\r'")
        let representation = try representation(of: view)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let cell = CGPoint(x: center.x + view.cellSize.width, y: center.y)
        #expect(isClose(color(in: representation, at: center), to: color(in: representation, at: cell)))
        #expect(window.firstResponder === view)
    }

    @Test func underlinesTheHoveredLinkInReverseVideo() async throws {
        let view = try await drawnView(running: "printf '\\033[?5hhttps://example.com'")
        let rect = view.rect(row: 0, columns: 0 ..< 1)
        view.updateHoveredLink(at: view.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil), modifierFlags: .command)
        let representation = try representation(of: view)
        let underline = color(in: representation, at: CGPoint(x: rect.midX, y: rect.maxY - 0.5))
        #expect(view.hoveredLink != nil)
        #expect(!isClose(underline, to: color(in: representation, at: CGPoint(x: 190, y: 90))))
    }

    @Test func hidesHiddenText() async throws {
        let blank = try image(of: try await drawnView(running: "printf ' \\r'"))
        let hidden = try image(of: try await drawnView(running: "printf '\\033[8mX\\r'"))
        #expect(hidden == blank)
    }

    @Test func sendsKeyPressesToTheSession() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        for characters in ["h", "i", "\r"] {
            view.keyDown(with: try keyDown(characters))
        }
        #expect(await session.linesAfterExit().contains("got hi"))
    }

    @Test func sendsTheCursorKeysInTheModeOfTheProcess() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[?1h'; dd bs=3 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        for await isEnabled in Observations({ session.terminal.usesApplicationCursorKeys }) where isEnabled {
            break
        }
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey))
        #expect(await session.linesAfterExit().contains("1b  4f  41"))
    }

    @Test(arguments: [(true, "1b  61"), (false, "c3  a5")])
    func sendsTheOptionKeyAsMetaWhenItIsOn(isOn: Bool, bytes: String) async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 2 | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.usesOptionAsMetaKey = isOn
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option))
        #expect(await session.linesAfterExit().contains(bytes))
    }

    @Test func sendsTheOptionArrowsAsWordMovement() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown(NSRightArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  62  1b  66  78"))
    }

    @Test(arguments: [
        (NSEvent.ModifierFlags([.control, .option]), "1b  5b  31  3b  37  44  1b  5b  31  3b  37  43  78"),
        (NSEvent.ModifierFlags([.shift, .option]), "1b  5b  31  3b  34  44  1b  5b  31  3b  34  43  78"),
    ])
    func sendsTheOtherModifiersOfTheOptionArrows(modifierFlags: NSEvent.ModifierFlags, bytes: String) async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 13 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: modifierFlags))
        view.keyDown(with: try keyDown(NSRightArrowFunctionKey, modifierFlags: modifierFlags))
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains(bytes))
    }

    @Test func sendsControlKeysThatTheInputSystemDrops() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        for key in ["/", "2", "6", "?"] {
            view.keyDown(with: try keyDown(key, modifierFlags: .control))
        }
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1f  00  1e  7f  78"))
    }

    @Test func leavesControlKeysToTheMarkedText() async throws {
        let session = TerminalSession(
            running: """
                stty raw -echo; echo ready
                while byte=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' '); [ "$byte" != 78 ]; do
                    echo "got $byte"
                done
                """
        )
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("2", modifierFlags: .control))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await !session.linesAfterExit().contains { $0.contains("got 00") })
    }

    @Test func replacesTheInsertedTextWithTheChosenAccent() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 4 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.insertText("e", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.selectedRange() == NSRange(location: 1, length: 0))
        let substring = view.attributedSubstring(forProposedRange: NSRange(location: 0, length: 1), actualRange: nil)
        #expect(substring?.string == "e")
        view.insertText("é", replacementRange: NSRange(location: 0, length: 1))
        #expect(await session.linesAfterExit().contains("65  7f  c3  a9"))
    }

    @Test func replacesTheInsertedTextWithTheMarkedAccent() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 3 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.insertText("e", replacementRange: NSRange(location: NSNotFound, length: 0))
        let original = view.selectedRange()
        view.setMarkedText(
            "é",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: original.location - 1, length: 1)
        )
        let marked = view.selectedRange()
        view.insertText("é", replacementRange: NSRange(location: marked.location - 1, length: 1))
        #expect(await session.linesAfterExit().contains("65  7f  c3"))
    }

    @Test func keepsTheTextBeforeAnotherKeyOrTheMarkedText() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 9 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.insertText("e", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey))
        view.insertText("é", replacementRange: NSRange(location: 0, length: 1))
        view.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.insertText("か", replacementRange: NSRange(location: 0, length: 1))
        #expect(await session.linesAfterExit().contains("65  1b  5b  44  c3  a9  e3  81  8b"))
    }

    @Test func leavesOptionKeysToTheMarkedText() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 4 | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.usesOptionAsMetaKey = true
        object_setClass(view.inputContext, ComposingInputContext.self)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown(NSRightArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("e3  81  8b  78"))
    }

    @Test func sendsTheOptionArrowsThatTheInputSystemReturns() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 8 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "か",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown(NSRightArrowFunctionKey, modifierFlags: .option))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  62  1b  66  e3  81  8b  78"))
    }

    @Test func sendsAKeyWithTwoCommandsOnce() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 7 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        let up = String(try #require(UnicodeScalar(NSUpArrowFunctionKey)))
        let optionUp = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option, .function, .numericPad],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: up,
                charactersIgnoringModifiers: up,
                isARepeat: false,
                keyCode: 126
            )
        )
        view.keyDown(with: optionUp)
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  5b  31  3b  33  41  78"))
    }

    @Test func doesNotSendCommandKeys() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.copy(nil)
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey, modifierFlags: [.command, .shift]))
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey, modifierFlags: [.command]))
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        view.keyDown(with: try keyDown("C", modifierFlags: [.command, .shift], keyCode: 8))
        view.keyDown(with: try keyDown("\r", modifierFlags: .command))
        view.keyDown(with: try keyDown("a"))
        #expect(await session.linesAfterExit().contains("61"))
    }

    @Test func sendsControlUForCommandDelete() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("\u{7F}", modifierFlags: .command))
        view.keyDown(with: try keyDown("\u{7F}", modifierFlags: [.command, .shift]))
        view.keyDown(with: try keyDown("\u{7F}", modifierFlags: [.command, .option]))
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("\u{7F}", modifierFlags: .command))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("15  15  c2  b4  78"))
    }

    @Test func passesCommandKeysToTheNextResponder() throws {
        let view = TerminalContentView(session: readingSession())
        let responder = KeyRecorder()
        view.nextResponder = responder
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        #expect(responder.keys == ["c"])
    }

    @Test func sendsTextFromTheInputSystem() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        view.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.keyDown(with: try keyDown("\r"))
        #expect(await session.linesAfterExit().contains("got é"))
    }

    @Test func keepsTheMarkedTextUntilTheInsert() {
        let view = TerminalContentView(session: readingSession())
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 0, length: 1))
        view.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
    }

    @Test func sendsTheMarkedTextWhenUnmarked() async throws {
        let session = TerminalSession(running: "stty -echo; echo ready; read line; printf %s \"$line\" | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.unmarkText()
        view.setMarkedText(
            "日本",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.unmarkText()
        view.unmarkText()
        view.keyDown(with: try keyDown("\r"))
        #expect(!view.hasMarkedText())
        #expect(await session.linesAfterExit().contains("e6  97  a5  e6  9c  ac"))
    }

    @Test func drawsTheMarkedText() throws {
        let view = TerminalContentView(session: readingSession())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let cursorImage = try image(of: view)
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(try image(of: view) != cursorImage)
        view.unmarkText()
        #expect(try image(of: view) == cursorImage)
    }

    @Test func drawsTheClausesOfTheMarkedText() throws {
        let view = TerminalContentView(session: readingSession())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let clauses = NSMutableAttributedString(
            string: "日本語入力",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        let selection = NSRange(location: 2, length: 3)
        let replacement = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText(clauses, selectedRange: selection, replacementRange: replacement)
        let first = NSAttributedString(string: "日本", attributes: [.font: view.font]).size().width
        let total = NSAttributedString(string: "日本語入力", attributes: [.font: view.font]).size().width
        let firstClause = CGRect(x: 0, y: 0, width: TerminalContentView.padding + first - 1, height: 100)
        let secondClause = CGRect(x: TerminalContentView.padding + first, y: 0, width: total - first, height: 100)
        let single = (try pixels(in: firstClause, of: view), try pixels(in: secondClause, of: view))
        clauses.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: selection)
        view.setMarkedText(clauses, selectedRange: selection, replacementRange: replacement)
        #expect(try pixels(in: firstClause, of: view) == single.0)
        #expect(try pixels(in: secondClause, of: view) != single.1)
        #expect(view.selectedRange() == selection)
        #expect(view.validAttributesForMarkedText() == [.underlineStyle, .markedClauseSegment])
        view.unmarkText()
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func drawsTheEndOfTheMarkedTextAtTheRightEdge(scale: CGFloat) async throws {
        let view = try await drawnView(running: "printf '\\033[49G'")
        let window = ScaledWindow(contentView: view)
        window.scale = scale
        let edge = CGRect(x: view.bounds.width - 2, y: 0, width: 2, height: view.bounds.height)
        let padding = try pixels(in: edge, of: view)
        #expect(view.bounds.contains(view.cursorRect))
        mark(9, in: view)
        let nine = try image(of: view)
        mark(10, in: view)
        #expect(try image(of: view) != nine)
        #expect(try pixels(in: edge, of: view) == padding)
        #expect(try pixels(in: edge.offsetBy(dx: -TerminalContentView.padding, dy: 0), of: view) != padding)
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func coversTheTextUnderTheMarkedTextAtTheRightEdge(scale: CGFloat) async throws {
        let full = try await drawnView(running: "printf '\\n%060d\\033[49G'")
        let empty = try await drawnView(running: "printf '\\n\\033[49G'")
        let windows = [ScaledWindow(contentView: full), ScaledWindow(contentView: empty)]
        for (window, view) in zip(windows, [full, empty]) {
            window.scale = scale
            mark(10, in: view)
        }
        let composition = full.rect(row: 1, columns: 39 ..< 52)
        #expect(try pixels(in: composition, of: full) == pixels(in: composition, of: empty))
    }

    @Test(arguments: [1, 2] as [CGFloat])
    func drawsTheMarkedTextAtTheCursorInTheFirstColumn(scale: CGFloat) async throws {
        let view = try await drawnView(running: "exit")
        let window = ScaledWindow(contentView: view)
        window.scale = scale
        let start = view.rect(row: 0, columns: 0 ..< 4)
        mark(9, in: view)
        let nine = try pixels(in: start, of: view)
        mark(40, in: view)
        #expect(try pixels(in: start, of: view) == nine)
    }

    @Test func placesTheInputWindowAtTheCursor() {
        let view = TerminalContentView(session: readingSession())
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 300, height: 150),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        let rect = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        #expect(rect.origin == CGPoint(x: 110, y: 343 - view.cellSize.height))
        #expect(rect.size == view.cellSize)
    }
}

@MainActor
private func readingSession() -> TerminalSession {
    TerminalSession(running: "read line; echo \"got $line\"")
}

@MainActor
private func drawnView(running script: String) async throws -> TerminalContentView {
    let session = TerminalSession(running: script)
    let view = TerminalContentView(session: session)
    view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    try session.start()
    await session.waitForExit()
    return view
}

@MainActor
private func focusedView(running script: String) async throws -> (view: TerminalContentView, window: KeyWindow) {
    let session = TerminalSession(running: script)
    let view = TerminalContentView(session: session)
    let window = KeyWindow(contentView: view)
    view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    try session.start()
    await session.waitForExit()
    return (view, window)
}

@MainActor
private func mark(_ count: Int, in view: TerminalContentView) {
    view.setMarkedText(
        String(repeating: "か", count: count),
        selectedRange: NSRange(location: count, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0)
    )
}

@MainActor
private func image(of view: NSView) throws -> Data {
    try #require(try representation(of: view).tiffRepresentation)
}

@MainActor
private func representation(of view: NSView) throws -> NSBitmapImageRep {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return representation
}

@MainActor
private func color(in representation: NSBitmapImageRep, at point: CGPoint) -> NSColor? {
    let scale = CGFloat(representation.pixelsWide) / representation.size.width
    return representation.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))
}

@MainActor
private func pixels(in rect: CGRect, of view: NSView) throws -> [NSColor?] {
    let representation = try representation(of: view)
    let scale = CGFloat(representation.pixelsWide) / representation.size.width
    return stride(from: Int(rect.minY * scale), to: Int(rect.maxY * scale), by: 1)
        .flatMap { y in
            stride(from: Int(rect.minX * scale), to: Int(rect.maxX * scale), by: 1)
                .map { x in representation.colorAt(x: x, y: y) }
        }
}

private func operatorCounts(in data: Data) throws -> (fills: Int, images: Int) {
    let document = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
    let page = try #require(document.page(at: 1))
    let table = try #require(CGPDFOperatorTableCreate())
    defer { CGPDFOperatorTableRelease(table) }
    CGPDFOperatorTableSetCallback(table, "f") { _, info in
        info?.assumingMemoryBound(to: (fills: Int, images: Int).self).pointee.fills += 1
    }
    CGPDFOperatorTableSetCallback(table, "Do") { _, info in
        info?.assumingMemoryBound(to: (fills: Int, images: Int).self).pointee.images += 1
    }
    var counts = (fills: 0, images: 0)
    let stream = CGPDFContentStreamCreateWithPage(page)
    defer { CGPDFContentStreamRelease(stream) }
    withUnsafeMutablePointer(to: &counts) {
        let scanner = CGPDFScannerCreate(stream, table, $0)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
    }
    return counts
}

private let red: [CGFloat] = [194 / 255, 54 / 255, 33 / 255]

private let highContrastPalette = TerminalPalette(
    foreground: Color(.sRGB, red: 0, green: 0, blue: 0),
    background: Color(.sRGB, red: 1, green: 1, blue: 1),
    cursor: Color(.sRGB, red: 0, green: 0, blue: 0),
    selection: Color(.sRGB, red: 0.7, green: 0.8, blue: 1),
    ansiColors: [Color(.sRGB, red: 0, green: 0, blue: 0), Color(.sRGB, red: 1, green: 0, blue: 0)]
        + Array(repeating: Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5), count: 14)
)

private func isClose(_ color: NSColor?, to other: NSColor?) -> Bool {
    guard let other = other?.usingColorSpace(.sRGB) else {
        return false
    }
    return isClose(color, to: [other.redComponent, other.greenComponent, other.blueComponent])
}

private func isClose(_ color: NSColor?, to components: [CGFloat]) -> Bool {
    guard let color = color?.usingColorSpace(.sRGB) else {
        return false
    }
    return zip([color.redComponent, color.greenComponent, color.blueComponent], components)
        .allSatisfy { abs($0 - $1) < 0.02 }
}

private final class ScaledWindow: NSWindow {
    var scale: CGFloat = 1

    override var backingScaleFactor: CGFloat {
        scale
    }
}

private final class FillView: NSView {
    var fills: [(rect: CGRect, color: NSColor)] = []

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (rect, color) in fills {
            color.setFill()
            backingAlignedRect(rect, options: .alignAllEdgesNearest).fill()
        }
    }
}

private final class ScaledKeyWindow: KeyWindow {
    var scale: CGFloat = 1

    override var backingScaleFactor: CGFloat {
        scale
    }
}

private final class ComposingInputContext: NSTextInputContext {
    override func handleEvent(_ event: NSEvent) -> Bool {
        client.hasMarkedText() || super.handleEvent(event)
    }
}

private final class KeyRecorder: NSResponder {
    var keys: [String?] = []

    override func keyDown(with event: NSEvent) {
        keys.append(event.charactersIgnoringModifiers)
    }
}
