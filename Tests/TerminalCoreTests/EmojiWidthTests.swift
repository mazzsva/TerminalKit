import Testing

@testable import TerminalCore

@Suite(.timeLimit(.minutes(1)))
struct EmojiWidthTests {
    @Test(
        arguments: [
            ("\u{1F44D}\u{1F3FD}", [2, 0]), ("\u{1F44D}\u{FE0F}\u{1F3FD}", [2, 0]),
            ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", [2, 0]), ("\u{1F9D1}\u{200D}\u{1F4BB}", [2, 0]),
            ("\u{1F1FA}\u{1F1F8}", [2, 0]), ("\u{261D}\u{1F3FD}", [2, 0]),
            ("\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", [2, 0]), ("\u{2764}\u{FE0F}\u{200D}\u{1F525}", [2, 0]),
            ("\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}", [2, 0]),
            ("\u{26A0}\u{FE0F}", [1]), ("\u{2764}\u{FE0F}", [1]), ("\u{27A1}\u{FE0F}", [1]),
            ("1\u{FE0F}\u{20E3}", [1]), ("\u{26A0}", [1]), ("\u{2714}", [1]), ("\u{23FA}", [1]),
            ("\u{23BF}", [1]), ("\u{25CF}", [1]), ("\u{1F1FA}", [1]), ("\u{1F1FA}\u{FE0F}", [1]),
        ] as [(String, [UInt8])])
    func measuresAnEmojiAsOneCharacter(text: String, widths: [UInt8]) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(text + "x")
        #expect(terminal.screen[0].prefix(widths.count + 1).map(\.width) == widths + [1])
        #expect(terminal.character(of: terminal.screen[0][0]) == Character(text))
        #expect(terminal.screen[0][widths.count] == Terminal.Cell(scalar: "x"))
        #expect(terminal.cursor == Terminal.Position(row: 0, column: widths.count + 1))
    }

    @Test(arguments: ["a", "\u{E9}", "1"])
    func keepsASkinToneOnALetterOrDigitInOneColumn(base: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(base + "\u{1F3FD}x")
        #expect(terminal.screen[0].prefix(3).map(\.width) == [1, 1, 1])
        #expect(terminal.screen[0].prefix(2).map(terminal.character(of:)) == [Character(base + "\u{1F3FD}"), "x"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test(arguments: ["\u{26A0}", "\u{A9}", "\u{1F1FA}"])
    func keepsASkinToneOnAnEmojiThatTakesNoSkinToneInOneColumn(base: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(base + "\u{1F3FD}x")
        #expect(terminal.screen[0].prefix(3).map(\.width) == [1, 1, 1])
        #expect(terminal.character(of: terminal.screen[0][0]) == Character(base + "\u{1F3FD}"))
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func repeatsTheEmojiThatASkinToneJoins() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F44D}\u{1F3FD}\u{1B}[b")
        #expect(terminal.screen[0].prefix(4).map(\.width) == [2, 0, 2, 0])
        #expect(terminal.character(of: terminal.screen[0][2]) == "\u{1F44D}")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 4))
    }

    @Test func keepsJoiningScalarsThatAreNotEmojiInTheirOwnCells() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1100}\u{1100}x")
        #expect(terminal.screen[0].prefix(5).map(\.width) == [2, 0, 2, 0, 1])
    }

    @Test func startsANewCellForAnEmojiAfterSixteenScalars() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F468}" + String(repeating: "\u{200D}\u{1F468}", count: 8) + "x")
        #expect(terminal.screen[0].prefix(5).map(\.width) == [2, 0, 2, 0, 1])
        #expect(terminal.character(of: terminal.screen[0][2]) == "\u{1F468}")
        #expect(terminal.screen[0][4] == Terminal.Cell(scalar: "x"))
    }

    @Test(
        arguments: [
            ("\u{1F1FA}", 4, 4, 11), ("\u{1F1E6}", 3, 2, 1_000), ("\u{1F1FF}", 3, 2, 1_000),
            ("\u{1F1FA}", 4, 2, 1_000), ("\u{1F1FA}", 1, 2, 1_000), ("\u{1F3FD}", 3, 2, 1_000),
        ] as [(String, Int, Int, Int)])
    func repeatsARegionalIndicatorOrSkinToneLikePrintingIt(text: String, columns: Int, rows: Int, count: Int) {
        var repeated = Terminal(columns: columns, rows: rows)
        var printed = repeated
        repeated.receive(text + "\u{1B}[\(count)b")
        printed.receive(String(repeating: text, count: count + 1))
        #expect(repeated.screen == printed.screen)
        #expect(repeated.cursor == printed.cursor)
    }

    @Test func pairsRegionalIndicatorsInOrder() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}\u{1F1EB}x")
        #expect(terminal.screen[0].prefix(6).map(\.width) == [2, 0, 2, 0, 1, 1])
        #expect(
            terminal.screen[0].prefix(5).map(terminal.character(of:)) == [
                "\u{1F1FA}\u{1F1F8}", " ", "\u{1F1EC}\u{1F1E7}", " ", "\u{1F1EB}",
            ])
    }

    @Test func keepsTwoEmojiInTwoCharacters() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F600}\u{1F600}\u{2764}\u{FE0F}\u{2764}\u{FE0F}")
        #expect(terminal.screen[0].prefix(6).map(\.width) == [2, 0, 2, 0, 1, 1])
        #expect(terminal.cursor.column == 6)
    }

    @Test func joinsAnEmojiAfterAJoinerThatEndsALine() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("\u{1F468}\u{200D}\u{1F469}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["\u{1F468}\u{200D}\u{1F469}", " "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test func waitsToWrapAfterAFlagThatEndsALine() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("a\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [1, 2, 0])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
        terminal.receive("b")
        #expect(terminal.character(of: terminal.screen[1][0]) == "b")
    }

    @Test func overwritesAFlagInTheLastColumnsWithoutAutowrap() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("\u{1B}[?7la\u{1F1FA}\u{1F1F8}\u{1B}[?7hb")
        #expect(terminal.screen[0].map(\.width) == [1, 1, 1])
        #expect(terminal.screen[0][2] == Terminal.Cell(scalar: "b"))
        #expect(terminal.screen[1][0] == Terminal.Cell())
    }

    @Test func keepsAFlagNarrowInTheLastColumn() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("ab\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [1, 1, 1])
        #expect(terminal.character(of: terminal.screen[0][2]) == "\u{1F1FA}\u{1F1F8}")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func printsAFlagInAOneColumnScreen() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [1])
        #expect(terminal.character(of: terminal.screen[0][0]) == "\u{1F1FA}\u{1F1F8}")
    }

    @Test func givesTheSecondHalfOfAFlagTheStyleOfTheFirstHalf() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[44m\u{1F1FA}\u{1B}[41m\u{1F1F8}")
        #expect(terminal.screen[0].prefix(2).map(\.style.background) == [.indexed(4), .indexed(4)])
    }

    @Test func clearsTheWideCharacterThatAFlagCovers() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a中b\u{1B}[1G\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [2, 0, 1, 1])
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["\u{1F1FA}\u{1F1F8}", " ", " ", "b"])
    }

    @Test func insertsTheSecondHalfOfAFlagInInsertMode() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("abc\u{1B}[1G\u{1B}[4h\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [2, 0, 1, 1, 1])
        #expect(terminal.screen[0].suffix(3).map(terminal.character(of:)) == ["a", "b", "c"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func keepsTheWideCharacterAfterAFlagInInsertMode() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("中b\u{1B}[1G\u{1B}[4h\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [2, 0, 2, 0, 1, 1])
        #expect(
            terminal.screen[0].map(terminal.character(of:)) == ["\u{1F1FA}\u{1F1F8}", " ", "中", " ", "b", " "])
    }

    @Test func keepsAFlagWideThroughAReflow() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("ab\u{1F1FA}\u{1F1F8}\r\nx")
        terminal.resize(columns: 3, rows: 3)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == "\u{1F1FA}\u{1F1F8}")
    }
}
