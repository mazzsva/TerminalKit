import AppKit
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
        ] as [(String, [Int])])
    func joinsTheCellsThatTerminalAppJoins(text: String, heads: [Int]) {
        let (line, graphemes) = cells(text)
        let joined = TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil)
        #expect(joined?.heads.keys.sorted() == heads)
    }

    @Test(
        arguments: [
            "\u{1F468}\u{200D}\u{1F469}", "\u{1F3F4}\u{E0067}", "a\u{1F3FD}", "\u{4E2D}\u{1F3FD}", "\u{1100}\u{1100}",
            "a\u{903}", "e\u{301}\u{903}", "\u{1F600}\u{1F600}", "ab", "a\u{20E3}", "\u{4E2D}\u{20E3}",
        ])
    func keepsTheCellsThatTerminalAppKeepsApart(text: String) {
        let (line, graphemes) = cells(text)
        #expect(TerminalContentView.joinedCells(in: line, graphemes: graphemes, order: nil) == nil)
    }

    @Test(
        arguments: [
            "\u{1F1FA}\u{1F1F8}", "\u{1F44D}\u{1F3FD}", "\u{261D}\u{1F3FD}", "1\u{FE0F}\u{20E3}", "#\u{FE0F}\u{20E3}",
            "\u{1F468}\u{200D}\u{1F469}",
        ])
    func leavesAnEmojiSequenceInOneCell(text: String) {
        let (line, graphemes) = cells(text)
        #expect(line[0].width == 2)
        #expect(graphemes.character(of: line[0]) == text)
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
