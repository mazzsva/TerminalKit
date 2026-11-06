import Testing

@testable import TerminalCore

struct EmojiWidthTests {
    @Test(
        arguments: [
            ("\u{1F44D}\u{1F3FD}", [2, 0, 2, 0]),
            ("\u{1F468}\u{200D}\u{1F469}", [2, 0, 1, 2, 0]),
            ("\u{1F1FA}\u{1F1F8}", [1, 1]),
            ("\u{2764}\u{FE0F}", [1]),
            ("1\u{FE0F}\u{20E3}", [1, 1]),
            ("\u{26A0}", [1]),
            ("\u{1F600}\u{1F600}", [2, 0, 2, 0]),
        ] as [(String, [UInt8])])
    func placesEachScalarInItsOwnCells(text: String, widths: [UInt8]) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(text + "x")
        #expect(terminal.screen[0].prefix(widths.count).map(\.width) == widths)
        #expect(terminal.screen[0][widths.count] == Terminal.Cell(scalar: "x"))
        #expect(terminal.cursor == Terminal.Position(row: 0, column: widths.count + 1))
    }

    @Test func keepsAVariationSelectorOnTheCharacter() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{2764}\u{FE0F}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "\u{2764}\u{FE0F}")
    }

    @Test func wrapsAWideCharacterThatDoesNotFit() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc\u{1F44D}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b", "c", " "])
        #expect(terminal.character(of: terminal.screen[1][0]) == "\u{1F44D}")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test func dropsAMarkAfterADroppedCharacterWithoutAutowrap() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[?7labc\u{301}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b"])
    }

    @Test func combinesAMarkWithTheLastCharacterThatFitsWithoutAutowrap() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[?7lab\u{301}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b\u{301}"])
    }

    @Test func combinesAMarkAfterAControlThatFollowsADrop() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[?7labc\r\u{1B}[?7hx\u{301}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["x\u{301}", "b"])
    }

    @Test func combinesAMarkAfterAResizeThatFollowsADrop() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[?7labc")
        terminal.resize(columns: 3, rows: 1)
        terminal.receive("\u{301}")
        #expect(terminal.screen[0].map(terminal.character(of:)).contains("a\u{301}"))
    }

    @Test func staysInOneColumnWithAOneColumnGrid() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("\u{1F44D}")
        #expect(terminal.screen[0][0].width == 1)
    }
}
