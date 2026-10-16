import Testing

@testable import TerminalCore

struct TerminalTests {
    @Test func startsWithABlankScreen() {
        let terminal = Terminal(columns: 4, rows: 2)
        #expect(lines(terminal) == ["    ", "    "])
    }

    @Test func printsCharacters() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("hé".utf8)
        #expect(lines(terminal) == ["hé  ", "    "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func wrapsAtTheEndOfALine() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcdef".utf8)
        #expect(lines(terminal) == ["abcd", "ef  "])
    }

    @Test func waitsForTheNextCharacterToWrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd".utf8)
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
        terminal.receive("\r\nef".utf8)
        #expect(lines(terminal) == ["abcd", "ef  "])
    }

    @Test func movesToANewLine() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\r\ncd".utf8)
        #expect(lines(terminal) == ["ab  ", "cd  "])
    }

    @Test func keepsTheColumnOnALineFeed() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\ncd".utf8)
        #expect(lines(terminal) == ["ab  ", "  cd"])
    }

    @Test func returnsToTheFirstColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc\rd".utf8)
        #expect(lines(terminal) == ["dbc ", "    "])
    }

    @Test func scrollsAtTheBottomOfTheScreen() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\r\ncd\r\nef".utf8)
        #expect(lines(terminal) == ["cd  ", "ef  "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test func scrollsWhenTheLastLineWraps() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcdefghij".utf8)
        #expect(lines(terminal) == ["efgh", "ij  "])
    }

    @Test func movesBackOnBackspace() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{8}c".utf8)
        #expect(lines(terminal) == ["ac  ", "    "])
    }

    @Test func stopsBackspaceAtTheFirstColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{8}a".utf8)
        #expect(lines(terminal) == ["a   ", "    "])
    }

    @Test func cancelsThePendingWrapOnBackspace() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{8}e".utf8)
        #expect(lines(terminal) == ["abed", "    "])
    }

    @Test func movesToTheNextTabStop() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb\tc".utf8)
        #expect(lines(terminal) == ["a       b       c   "])
    }

    @Test func stopsTabsAtTheLastColumn() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\t\ta".utf8)
        #expect(lines(terminal) == ["         a"])
    }

    @Test(arguments: [
        ("A", Terminal.Position(row: 2, column: 4)),
        ("B", Terminal.Position(row: 6, column: 4)),
        ("C", Terminal.Position(row: 4, column: 6)),
        ("D", Terminal.Position(row: 4, column: 2)),
        ("E", Terminal.Position(row: 6, column: 0)),
        ("F", Terminal.Position(row: 2, column: 0)),
    ])
    func movesTheCursorRelativeToItsPosition(final: String, position: Terminal.Position) {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\n\n\n\n    \u{1B}[2\(final)".utf8)
        #expect(terminal.cursor == position)
    }

    @Test func movesTheCursorOneStepByDefault() {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\u{1B}[B\u{1B}[0C".utf8)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func keepsTheCursorOnTheScreen() {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\u{1B}[99B\u{1B}[99C".utf8)
        #expect(terminal.cursor == Terminal.Position(row: 9, column: 9))
        terminal.receive("\u{1B}[99A\u{1B}[99D".utf8)
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
    }
}

private func lines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { String($0.map(\.character)) }
}
