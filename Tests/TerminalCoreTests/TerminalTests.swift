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
}

private func lines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { String($0.map(\.character)) }
}
