import AppKit
import SwiftUI
import TerminalCore
import Testing

@testable import TerminalKit

@MainActor
struct TerminalJoinedCellTests {
    @Test(
        arguments: [
            ("\u{915}\u{93E}", [0]),
            ("\u{915}\u{93E}\u{915}\u{93F}", [0, 2]),
            ("\u{915}\u{94D}\u{937}", [0]),
            ("\u{E01}\u{E33}", [0]),
            (thumbWithSkinTone, [0]),
            (family, [0]),
            (keycap, [0]),
            (flagOfEngland, [0]),
            (family + thumbWithSkinTone, [0, 8]),
        ] as [(String, [Int])])
    func joinsTheCellsThatTerminalAppJoins(text: String, heads: [Int]) {
        let (line, graphemes) = cells(text)
        let joined = TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil)
        #expect(joined?.heads.keys.sorted() == heads)
    }

    @Test(
        arguments: [
            "a\u{1F3FD}", "\u{4E2D}\u{1F3FD}", "\u{263A}\u{1F3FD}", "\u{1100}\u{1100}", "a\u{903}", "e\u{301}\u{903}",
            "\u{1F600}\u{1F600}", "ab", "a\u{20E3}", "\u{4E2D}\u{20E3}", "a\u{200D}b", "1\u{903}",
        ])
    func keepsTheCellsThatTerminalAppKeepsApart(text: String) {
        let (line, graphemes) = cells(text)
        #expect(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil) == nil)
    }

    @Test func leavesAFlagInOneCell() {
        let (line, graphemes) = cells("\u{1F1FA}\u{1F1F8}")
        #expect(line[0].width == 2)
        #expect(graphemes.character(of: line[0]) == "\u{1F1FA}\u{1F1F8}")
        #expect(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil) == nil)
    }

    @Test func keepsCellsWithDifferentBackgroundsApart() {
        let (line, graphemes) = cells("\u{915}\u{1B}[41m\u{93E}")
        #expect(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil) == nil)
    }

    @Test func recordsTheEndAndTheFollowers() throws {
        let (line, graphemes) = cells("x\u{915}\u{94D}\u{937}y")
        let joined = try #require(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil))
        #expect(joined.heads[1]?.text == "\u{915}\u{94D}\u{937}")
        #expect(joined.heads[1]?.end == 3)
        #expect(joined.headsOfFollowers == [2: 1])
    }

    @Test func drawsJoinedCellsAsOneShape() async throws {
        let shape = try await drawn("\u{915}\u{93F}")
        let apart = try await drawn("\u{915} \u{93F}")
        let rect = shape.rect(row: 0, columns: 0 ..< 1)
        #expect(try image(of: shape, in: rect) != image(of: apart, in: rect))
    }

    @Test func drawsTheWholeShapeOverACursorOnItsSecondCell() async throws {
        let shape = try await focused("\u{915}\u{93F}\\b")
        let apart = try await focused(" \u{93F}\\b")
        let blank = try await focused("  \\b")
        let rect = shape.view.cursorRect
        #expect(shape.view.cursorRect == apart.view.cursorRect)
        #expect(try image(of: shape.view, in: rect) != image(of: apart.view, in: rect))
        #expect(try image(of: shape.view, in: rect) != image(of: blank.view, in: rect))
    }

    @Test func clipsTheShapeToTheCursor() async throws {
        let shape = try await focused("\u{915}\u{93F}\\b")
        let hidden = try await focused("\\033[?25l\u{915}\u{93F}\\b")
        let first = shape.view.rect(row: 0, columns: 0 ..< 1)
        #expect(try image(of: shape.view, in: first) == image(of: hidden.view, in: first))
    }

    @Test func keepsTheCursorCellUnderline() async throws {
        let marked = try await focused("\u{915}\\033[4m\u{93E}\\b")
        let plain = try await focused("\u{915}\u{93E}\\b")
        let rect = marked.view.cursorRect
        #expect(try image(of: marked.view, in: rect) != image(of: plain.view, in: rect))
    }

    @Test(arguments: ["\u{5D0}\u{903}", "\u{D4E}\u{5D0}"])
    func keepsMixedDirectionCellsApart(text: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        _ = terminal.receive(Array(text.utf8))
        let line = terminal.screen[0]
        let order = TerminalContentView.visualOrder(of: line, graphemes: terminal.graphemes)
        #expect(order != nil)
        #expect(TerminalContentView.joinedCells(in: line, graphemes: terminal.graphemes, order: order) == nil)
    }

    @Test(arguments: ["\u{1B}[7;31m\u{915}\u{1B}[32m\u{93E}", "\u{915}\u{1B}[8m\u{93E}"])
    func keepsCellsWithDifferentPaintApart(text: String) {
        let (line, graphemes) = cells(text)
        #expect(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil) == nil)
    }

    @Test func stopsAtTheByteLimit() throws {
        let (line, graphemes) = cells("\u{915}" + String(repeating: "\u{903}", count: 200), columns: 201)
        let joined = try #require(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil))
        let text = try #require(joined.heads[0]?.text)
        #expect(text.utf8.count <= 258)
        #expect(text.utf8.count >= 256)
    }

    @Test func drawsTheCellAfterTheByteLimitApart() async throws {
        let marks = String(repeating: "\u{FE00}", count: 83)
        let atTheLimit = "\u{915}\u{34F}\u{34F}" + marks
        let pastTheLimit = "\u{915}\u{34F}\u{FE00}" + marks
        #expect(atTheLimit.utf8.count == 256 && pastTheLimit.utf8.count == 257)
        let limit = try await drawn(atTheLimit + "\u{903}")
        let apart = try await drawn(pastTheLimit + "\u{903}")
        let rect = limit.rect(row: 0, columns: 1 ..< 2)
        #expect(try image(of: limit, in: rect) == image(of: apart, in: rect))
    }

    @Test func drawsTheCursorTextInItsOwnStyleAfterAShape() async throws {
        let shape = try await focused("\\033[32m\u{915}\u{93F}\\033[my\\b")
        let spaces = try await focused("\\033[32m  \\033[my\\b")
        let rect = shape.view.cursorRect
        #expect(try image(of: shape.view, in: rect) == image(of: spaces.view, in: rect))
    }

    @Test func expandsARangeToItsShape() throws {
        let (line, graphemes) = cells("x\u{915}\u{94D}\u{937}y")
        let joined = try #require(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil))
        #expect(joined.expanded(2 ..< 3) == 1 ..< 3)
        #expect(joined.expanded(1 ..< 2) == 1 ..< 3)
        #expect(joined.expanded(0 ..< 1) == 0 ..< 1)
    }

    @Test func keepsCellsJoinedInALineWithRightToLeftText() async throws {
        let shape = try await drawn("\u{915}\u{93F} \u{5D0}")
        let apart = try await drawn("\u{915} \u{93F}\u{5D0}")
        let rect = shape.rect(row: 0, columns: 0 ..< 1)
        #expect(try image(of: shape, in: rect) != image(of: apart, in: rect))
    }

    @Test(arguments: [(thumbWithSkinTone, 4), (family, 8), (keycap, 2), (flagOfEngland, 8)])
    func drawsAnEmojiSequenceAsOneGlyphInItsFirstCells(sequence: String, width: Int) async throws {
        let view = try await drawn(sequence)
        view.palette.background = Color(.sRGB, red: 1, green: 1, blue: 1)
        let string = StringView(frame: view.frame, text: sequence, font: view.font)
        string.origin = CGPoint(x: TerminalContentView.padding, y: TerminalContentView.topPadding + view.font.ascender)
        let cells = view.rect(row: 0, columns: 0 ..< width)
        #expect(try image(of: view, in: cells) == image(of: string, in: cells))
        if width > 3 {
            let rest = view.rect(row: 0, columns: 3 ..< width)
            string.text = ""
            #expect(try image(of: view, in: rest) == image(of: string, in: rest))
        }
    }

    @Test func drawsEachPartOfASequenceThatTheLastColumnCuts() async throws {
        let cut = try await drawn("\\033[1;79H\(thumbWithSkinTone)")
        let apart = try await drawn("\\033[1;79H\u{1F44D}\\r\\n\u{1F3FD}")
        let blank = try await drawn("")
        #expect(cut.session.terminal.screen[1][0].width == 2)
        let rows = cut.rect(row: 0, columns: 0 ..< 80).union(cut.rect(row: 1, columns: 0 ..< 80))
        for view in [cut, apart, blank] {
            view.frame.size = CGSize(width: rows.maxX + TerminalContentView.padding, height: 100)
        }
        #expect(try image(of: cut, in: rows) == image(of: apart, in: rows))
        #expect(try image(of: cut, in: rows) != image(of: blank, in: rows))
    }

    private func focused(_ text: String) async throws -> (view: TerminalContentView, window: KeyWindow) {
        let session = TerminalSession(running: "printf '\(text)'")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.palette.cursor = .red
        try session.start()
        await session.waitForExit()
        #expect(window.firstResponder === view)
        return (view, window)
    }

    private func cells(_ text: String, columns: Int = 20) -> (Terminal.Line, Terminal.Graphemes) {
        var terminal = Terminal(columns: columns, rows: 1)
        _ = terminal.receive(Array(text.utf8))
        return (terminal.screen[0], terminal.graphemes)
    }

    private func drawn(_ text: String) async throws -> TerminalContentView {
        let session = TerminalSession(running: "printf '\\033[?25l\(text)'")
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        await session.waitForExit()
        return view
    }

    private func image(of view: NSView, in rect: CGRect) throws -> Data {
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: rect))
        view.cacheDisplay(in: rect, to: representation)
        return try #require(representation.tiffRepresentation)
    }
}

@MainActor
struct TerminalDirectionalControlTests {
    @Test(arguments: ["\u{202E}", "\u{2067}", "\u{202B}"])
    func ignoresADirectionalControlInTheVisualOrder(control: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        _ = terminal.receive(Array("x\(control)ab \u{5D0}".utf8))
        let order = TerminalContentView.visualOrder(of: terminal.screen[0], graphemes: terminal.graphemes)
        #expect(order?.columns.prefix(4).elementsEqual(Array(0 ..< 4)) == true)
    }

    @Test func keepsTheOrderWithAByteOrderMark() {
        var terminal = Terminal(columns: 10, rows: 1)
        _ = terminal.receive(Array("a\u{FEFF}b".utf8))
        #expect(TerminalContentView.visualOrder(of: terminal.screen[0], graphemes: terminal.graphemes) == nil)
    }
}

private let thumbWithSkinTone = "\u{1F44D}\u{1F3FD}"
private let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
private let keycap = "1\u{FE0F}\u{20E3}"
private let flagOfEngland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"

private final class StringView: NSView {
    var text: String
    var origin = CGPoint.zero
    private let font: NSFont

    init(frame: CGRect, text: String, font: NSFont) {
        self.text = text
        self.font = font
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setFill()
        dirtyRect.fill()
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for run in GlyphCache().entry(for: text, font: font, index: 0, isMirrored: false).runs {
            let positions = run.positions.map { CGPoint(x: origin.x + $0.x, y: $0.y - origin.y) }
            CTFontDrawGlyphs(run.font, run.glyphs, positions, run.glyphs.count, context)
        }
    }
}
