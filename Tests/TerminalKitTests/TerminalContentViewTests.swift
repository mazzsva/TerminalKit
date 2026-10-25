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
        view.fit(to: CGSize(width: 8 + view.cellSize.width * 100.5, height: 8 + view.cellSize.height * 30.5))
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

    @Test func givesTheSizeToAnotherViewWhenTheSizingViewIsTooSmall() {
        let session = TerminalSession(running: "exit")
        let first = TerminalContentView(session: session)
        let second = TerminalContentView(session: session)
        first.fit(to: cells(100.5, 30.5, in: first))
        second.fit(to: cells(60.5, 20.5, in: second))
        #expect(session.terminal.columns == 100)
        first.fit(to: .zero)
        second.fit(to: cells(60.5, 20.5, in: second))
        #expect(session.sizingView === second)
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
        CGSize(width: 8 + view.cellSize.width * columns, height: 8 + view.cellSize.height * rows)
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
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
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

    @Test func drawsTheCharacterUnderTheCursor() async throws {
        var palette = TerminalPalette.standard
        palette.cursor = .red
        let (character, characterWindow) = try await focusedView(running: "printf 'X\\b'")
        let (space, spaceWindow) = try await focusedView(running: "printf ' \\b'")
        character.palette = palette
        space.palette = palette
        #expect(try pixels(in: character.cursorRect, of: character) != pixels(in: space.cursorRect, of: space))
        #expect(characterWindow.firstResponder === character && spaceWindow.firstResponder === space)
    }

    @Test func coversAWideCharacterWithTheCursor() async throws {
        let view = try await drawnView(running: "printf '中\\b\\b'")
        #expect(view.cursorRect.width == 2 * view.cellSize.width)
    }

    @Test func hidesTheCursor() async throws {
        let view = try await drawnView(running: "printf '\\033[?25l'")
        let representation = try representation(of: view)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        #expect(color(in: representation, at: center) == color(in: representation, at: CGPoint(x: 190, y: 90)))
    }

    @Test func drawsTheTextAfterAWideCharacterInItsCell() async throws {
        let wide = try await drawnView(running: "printf '中x\\n'")
        let narrow = try await drawnView(running: "printf '  x\\n'")
        let cell = CGRect(
            x: 4 + 2 * wide.cellSize.width,
            y: 4,
            width: wide.cellSize.width,
            height: wide.cellSize.height
        )
        #expect(try pixels(in: cell, of: wide) == pixels(in: cell, of: narrow))
    }

    @Test func drawsEachCharacterInItsCellWithAProportionalFont() async throws {
        let narrow = try await drawnView(running: "printf 'iiiiW\\n'")
        let spaced = try await drawnView(running: "printf '    W\\n'")
        for view in [narrow, spaced] {
            view.font = .systemFont(ofSize: 13)
        }
        let cell = CGRect(
            x: 4 + 4 * narrow.cellSize.width,
            y: 4,
            width: narrow.cellSize.width,
            height: narrow.cellSize.height
        )
        #expect(try pixels(in: cell, of: narrow) == pixels(in: cell, of: spaced))
    }

    @Test(arguments: ["e\\314\\201", "\\360\\237\\230\\200", "\\344\\270\\255", "\\320\\226"])
    func drawsACharacterOutsideASCII(character: String) async throws {
        let blank = try await drawnView(running: "printf '  \\r'")
        let drawn = try await drawnView(running: "printf '\(character)\\r'")
        let cells = CGRect(x: 4, y: 4, width: 2 * drawn.cellSize.width, height: drawn.cellSize.height)
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
            x: 4 + first.cellSize.width, y: 4, width: 2 * first.cellSize.width, height: first.cellSize.height)
        #expect(try pixels(in: cells, of: first) != pixels(in: cells, of: second))
        #expect(try pixels(in: cells, of: first) == pixels(in: cells, of: spaced))
    }

    @Test func underlinesARunWithAWideCharacter() async throws {
        let view = try await drawnView(running: "printf '\\033[4ma\\344\\270\\255b\\033[m\\r'")
        let font = view.fonts.regular
        let y = 4 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        let underline = stride(from: 4 + view.cellSize.width / 4, to: 4 + view.cellSize.width * 3.75, by: 1)
            .map { color(in: representation, at: CGPoint(x: $0, y: y)) }
        #expect(underline.allSatisfy { $0 != background })
    }

    @Test func drawsTheBackgroundColor() async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[m'")
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 194 / 255) < 0.02)
        #expect(abs(color.greenComponent - 54 / 255) < 0.02)
        #expect(abs(color.blueComponent - 33 / 255) < 0.02)
    }

    @Test func drawsTheBackgroundColorWithoutASeamBetweenRuns() async throws {
        let view = try await drawnView(running: "printf '\\033[44m        \\033[31m        \\033[m'")
        #expect(view.cellSize.width != view.cellSize.width.rounded())
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let fill = color(in: try representation(of: view), at: center)
        let edge = CGRect(x: 4 + view.cellSize.width * 8 - 2, y: center.y, width: 4, height: 1)
        #expect(try pixels(in: edge, of: view).allSatisfy { isClose($0, to: fill) })
    }

    @Test func drawsTheSelectionWithoutASeamAtItsEdge() async throws {
        let view = try await drawnView(running: "printf '        \\033[44m        \\033[m'")
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 8))
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let representation = try representation(of: view)
        let selected = color(in: representation, at: center)
        let fill = color(in: representation, at: CGPoint(x: center.x + view.cellSize.width * 12, y: center.y))
        let edge = CGRect(x: 4 + view.cellSize.width * 8 - 2, y: center.y, width: 4, height: 1)
        #expect(!isClose(selected, to: fill))
        #expect(try pixels(in: edge, of: view).allSatisfy { isClose($0, to: selected) || isClose($0, to: fill) })
    }

    @Test(
        arguments: [
            ("█", [CGRect(x: 0, y: 0, width: 1, height: 1)]), ("▀", [CGRect(x: 0, y: 0, width: 1, height: 0.5)]),
            ("▁", [CGRect(x: 0, y: 7.0 / 8, width: 1, height: 1.0 / 8)]),
            ("▄", [CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]),
            ("▉", [CGRect(x: 0, y: 0, width: 7.0 / 8, height: 1)]),
            ("▌", [CGRect(x: 0, y: 0, width: 0.5, height: 1)]), ("▐", [CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]),
            ("▔", [CGRect(x: 0, y: 0, width: 1, height: 1.0 / 8)]),
            ("▕", [CGRect(x: 7.0 / 8, y: 0, width: 1.0 / 8, height: 1)]),
            ("▖", [CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)]),
            ("▘", [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)]),
            ("▝", [CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]),
            ("▗", [CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]),
            ("▛", [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)]),
            ("▙", [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]),
            ("▚", [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]),
            ("▜", [CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]),
            ("▞", [CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)]),
            ("▟", [CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]),
        ] as [(String, [CGRect])])
    func drawsABlockElementAsARectangle(character: String, units: [CGRect]) async throws {
        let view = try await drawnView(running: "printf '\\033[31m\(character)\\n'")
        let cell = CGRect(x: 4, y: 4, width: view.cellSize.width, height: view.cellSize.height)
        let filled = try units.map {
            try pixels(
                in: $0.applying(
                    CGAffineTransform(translationX: 4, y: 4).scaledBy(x: view.cellSize.width, y: view.cellSize.height)),
                of: view)
        }
        #expect(filled.joined().allSatisfy { isClose($0, to: red) })
        #expect(try pixels(in: cell, of: view).count { isClose($0, to: red) } == filled.joined().count)
    }

    @Test(arguments: ["▏", "▕"])
    func drawsAnEighthBlockInEveryColumnAtAStandardScale(character: String) async throws {
        let view = try await drawnView(running: "printf '\\033[31m\(String(repeating: character, count: 20))\\n'")
        let window = StandardScaleWindow(contentView: view)
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let (width, y) = (view.cellSize.width, 4 + view.cellSize.height / 2)
        let cells = (0 ..< 20).map { CGRect(x: 4 + CGFloat($0) * width, y: y, width: width, height: 1) }
            .map { view.backingAlignedRect($0, options: .alignAllEdgesNearest) }
        let background = color(in: try representation(of: view), at: CGPoint(x: 190, y: 90))
        let ink = try cells.map { try pixels(in: $0, of: view).filter { !isClose($0, to: background) } }
        #expect(ink.allSatisfy { $0.count == 1 && isClose($0[0], to: ink[0][0]) })
        #expect(window.contentView === view)
    }

    @Test func drawsAShadeWithTheForegroundAtPartialAlpha() async throws {
        let view = try await drawnView(running: "printf '\\033[4;31m \\n░▒▓ \\033[2;24m█\\n'")
        let font = view.fonts.regular
        let underline = 4 + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        let foreground = NSColor(srgbRed: red[0], green: red[1], blue: red[2], alpha: 1)
        func point(row: Int, column: Int, y: CGFloat) -> CGPoint {
            CGPoint(x: 4 + (CGFloat(column) + 0.5) * view.cellSize.width, y: y + CGFloat(row) * view.cellSize.height)
        }
        for (column, alpha): (Int, CGFloat) in [(0, 0.25), (1, 0.5), (2, 0.75), (4, 0.5)] {
            let blended = background?.blended(withFraction: alpha, of: foreground)
            let center = point(row: 1, column: column, y: 4 + view.cellSize.height / 2)
            #expect(isClose(color(in: representation, at: center), to: blended))
        }
        let plainUnderline = try #require(color(in: representation, at: point(row: 0, column: 0, y: underline)))
        #expect(isClose(color(in: representation, at: point(row: 1, column: 3, y: underline)), to: plainUnderline))
        #expect(!isClose(plainUnderline, to: background))
    }

    @Test func drawsAStackOfFullBlocksWithoutAGap() async throws {
        let view = try await drawnView(running: "printf '\\033[31m█\\n█\\n█\\n'")
        let column = CGRect(x: 4 + view.cellSize.width / 2, y: 4, width: 1, height: 3 * view.cellSize.height)
        #expect(try pixels(in: column, of: view).allSatisfy { isClose($0, to: red) })
    }

    @Test func drawsARowOfFullBlocksWithoutAGap() async throws {
        let view = try await drawnView(running: "printf '\\033[31m███\\n'")
        let row = CGRect(x: 4, y: 4 + view.cellSize.height / 2, width: 3 * view.cellSize.width, height: 1)
        #expect(try pixels(in: row, of: view).allSatisfy { isClose($0, to: red) })
    }

    @Test func drawsTheScrollback() async throws {
        let session = TerminalSession(running: "printf '\\033[41m  \\033[m'; seq 1 30")
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 200, height: 100))
        try session.start()
        await session.waitForExit()
        view.fit(to: CGSize(width: 200, height: 100))
        #expect(!session.terminal.scrollback.isEmpty)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 194 / 255) < 0.02)
    }

    @Test func drawsWithThePalette() async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[m'")
        var palette = TerminalPalette.standard
        palette.background = Color(.sRGB, red: 0.2, green: 0.3, blue: 0.4)
        palette.ansiColors[1] = Color(.sRGB, red: 0.4, green: 0.6, blue: 0.2)
        view.palette = palette
        let representation = try representation(of: view)
        let cell = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
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
            .map { CGPoint(x: 4 + view.cellSize.width * (CGFloat($0) + 0.5), y: 4 + view.cellSize.height / 2) }
        let fill: [CGFloat] = count > 2 ? [0.1, 0.9, 0.5] : [203.0 / 255, 204.0 / 255, 205.0 / 255]
        let brightFill: [CGFloat] = count > 2 ? [0.1, 0.9, 0.5] : [233.0 / 255, 235.0 / 255, 235.0 / 255]
        #expect(isClose(color(in: representation, at: points[0]), to: [0.4, 0.6, 0.2]))
        #expect(isClose(color(in: representation, at: points[1]), to: fill))
        #expect(isClose(color(in: representation, at: points[2]), to: brightFill))
    }

    @Test func drawsTheForegroundColor() async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let red = try image(of: try await drawnView(running: "printf '\\033[31mX\\r'"))
        #expect(red != plain)
    }

    @Test(arguments: ["1", "2", "3", "4", "9"])
    func drawsTheTextStyle(parameter: String) async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let styled = try image(of: try await drawnView(running: "printf '\\033[\(parameter)mX\\r'"))
        #expect(styled != plain)
    }

    @Test func drawsInverseText() async throws {
        let view = try await drawnView(running: "printf '\\033[7m  \\033[m'")
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let representation = try representation(of: view)
        #expect(color(in: representation, at: center) != color(in: representation, at: CGPoint(x: 190, y: 90)))
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
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 3 | od -An -tx1")
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
        #expect(await session.linesAfterExit().contains("15  15  78"))
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

    @Test func dropsTheMarkedTextWhenUnmarked() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.unmarkText()
        view.keyDown(with: try keyDown("\r"))
        #expect(!view.hasMarkedText())
        #expect(await session.linesAfterExit().contains("got"))
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
        #expect(rect.origin == CGPoint(x: 104, y: 346 - view.cellSize.height))
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

private let red: [CGFloat] = [194 / 255, 54 / 255, 33 / 255]

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

private final class StandardScaleWindow: NSWindow {
    override var backingScaleFactor: CGFloat {
        1
    }
}

private final class KeyRecorder: NSResponder {
    var keys: [String?] = []

    override func keyDown(with event: NSEvent) {
        keys.append(event.charactersIgnoringModifiers)
    }
}
