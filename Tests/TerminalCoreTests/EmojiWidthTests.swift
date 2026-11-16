import Testing

@testable import TerminalCore

@Suite(.timeLimit(.minutes(1)))
struct EmojiWidthTests {
    static let flag = "\u{1F1FA}\u{1F1F8}"

    static let columnsAfterPrinting: [(String, Int)] = [
        ("\u{1F44D}\u{1F3FD}", 4),
        ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", 8),
        ("\u{2764}\u{FE0F}", 1),
        ("\u{263A}\u{FE0F}", 1),
        ("\u{1F1EE}\u{1F1F9}", 2),
        ("\u{4E2D}\u{6587}\u{5B57}", 6),
        ("e\u{301}", 1),
        ("abc", 3),
    ]

    @Test(arguments: columnsAfterPrinting)
    func movesTheCursorByTheWidthOfTheTextInOneWrite(text: String, column: Int) {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive(text)
        #expect(terminal.cursor == Terminal.Position(row: 0, column: column))
    }

    @Test(arguments: columnsAfterPrinting)
    func movesTheCursorByTheWidthOfTheTextInOneWritePerScalar(text: String, column: Int) {
        var terminal = Terminal(columns: 20, rows: 1)
        for scalar in text.unicodeScalars {
            terminal.receive(String(scalar))
        }
        #expect(terminal.cursor == Terminal.Position(row: 0, column: column))
    }

    @Test(arguments: ["\u{2764}", "\u{2764}\u{FE0E}", "\u{26A0}", "\u{1F1FA}", "\u{200D}", "\u{20E3}"])
    func keepsTheWidthOfACharacterThatIsNotAnEmojiSequence(text: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(text)
        let width = text.unicodeScalars.first?.width ?? 0
        #expect(terminal.cursor.column == width)
        #expect(terminal.character(of: terminal.screen[0][0]) == text)
    }

    @Test func pairsRegionalIndicatorsInOrder() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F1FA}\u{1F1F8}\u{1F1EC}\u{1F1E7}\u{1F1EB}x")
        #expect(terminal.screen[0].prefix(6).map(\.width) == [2, 0, 2, 0, 1, 1])
        #expect(terminal.character(of: terminal.screen[0][0]) == Self.flag)
        #expect(terminal.cursor.column == 6)
    }

    @Test func placesARegionalIndicatorAfterACursorMoveAsItsOwnCharacter() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F1FA}\u{1B}[1;2H\u{1F1F8}")
        #expect(terminal.screen[0].prefix(3).map(\.width) == [1, 1, 1])
        #expect(terminal.character(of: terminal.screen[0][0]) == "\u{1F1FA}")
        #expect(terminal.character(of: terminal.screen[0][1]) == "\u{1F1F8}")
    }

    @Test func widensAClusterInTheMiddleOfALineLikeAWideCharacter() {
        var emoji = Terminal(columns: 4, rows: 1)
        emoji.receive("a\u{4E2D}b\u{1B}[1G\(Self.flag)")
        var wide = Terminal(columns: 4, rows: 1)
        wide.receive("a\u{4E2D}b\u{1B}[1G\u{4E2D}")
        #expect(emoji.screen[0].map(\.width) == wide.screen[0].map(\.width))
        #expect(emoji.screen[0].dropFirst().map(emoji.character(of:)) == [" ", " ", "b"])
        #expect(emoji.cursor == wide.cursor)
    }

    @Test func wrapsAClusterThatWidensInTheLastColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc" + Self.flag + "x")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b", "c", " "])
        #expect(terminal.screen[0][3] == .padding)
        #expect(terminal.screen[0].isWrapped)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == Self.flag)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 3))
    }

    @Test func wrapsAClusterThatWidensInTheLastColumnOfAScrollRegion() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("\u{1B}[3;1Hzz\u{1B}[1;2r\u{1B}[2;1Habc" + Self.flag + "x")
        #expect(terminal.screen[0].isWrapped)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == Self.flag)
        #expect(terminal.screen[2].prefix(2).map(terminal.character(of:)) == ["z", "z"])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 3))
    }

    @Test func widensAClusterThatEndsAtTheLastColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab" + Self.flag)
        #expect(terminal.screen[0].map(\.width) == [1, 1, 2, 0])
        terminal.receive("x")
        #expect(terminal.character(of: terminal.screen[1][0]) == "x")
    }

    @Test func keepsAClusterInTheLastColumnWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labc" + Self.flag)
        #expect(terminal.screen[0].map(\.width) == [1, 1, 1, 1])
        #expect(terminal.character(of: terminal.screen[0][3]) == Self.flag)
        #expect(terminal.screen[1].allSatisfy { $0 == Terminal.Cell() })
    }

    @Test func dropsTheTextAfterAClusterThatWidensToTheLastColumnWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?7lab" + Self.flag + "x")
        #expect(terminal.screen[0].map(\.width) == [1, 1, 2, 0])
        #expect(terminal.character(of: terminal.screen[0][2]) == Self.flag)
    }

    @Test func insertsTheSecondCellOfAClusterInInsertMode() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("abc\u{1B}[1G\u{1B}[4h" + Self.flag)
        #expect(terminal.screen[0].prefix(5).map(\.width) == [2, 0, 1, 1, 1])
        #expect(terminal.screen[0].dropFirst(2).prefix(3).map(terminal.character(of:)) == ["a", "b", "c"])
        #expect(terminal.cursor.column == 2)
    }

    @Test(arguments: [
        "\u{1B}[1G\u{1B}[@", "\u{1B}[1G\u{1B}[P", "\u{1B}[3G\u{1B}[1K", "\u{1B}[3Gy", "\u{1B}[2Gy", "\u{1B}[2X",
    ])
    func editsAClusterLikeAWideCharacter(edit: String) {
        var emoji = Terminal(columns: 6, rows: 1)
        emoji.receive("a\(Self.flag)b\u{1B}[2G" + edit)
        var wide = Terminal(columns: 6, rows: 1)
        wide.receive("a\u{4E2D}b\u{1B}[2G" + edit)
        #expect(emoji.screen[0].map(\.width) == wide.screen[0].map(\.width))
        #expect(
            emoji.screen[0].map(emoji.character(of:)).map { $0 == Self.flag ? "\u{4E2D}" : $0 }
                == wide.screen[0].map(wide.character(of:)))
        #expect(emoji.cursor == wide.cursor)
    }

    @Test func keepsAClusterWideThroughAReflow() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("ab\(Self.flag)\r\nx")
        terminal.resize(columns: 3, rows: 3)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == Self.flag)
    }

    @Test func limitsALongRunOfCombiningMarks() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("e" + String(repeating: "\u{301}", count: 100_000) + "x")
        #expect(terminal.character(of: terminal.screen[0][0]).utf8.count <= 1_024)
        #expect(terminal.screen[0][1] == Terminal.Cell(scalar: "x"))
    }

    @Test func wrapsAWideCharacterThatDoesNotFit() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc\u{1F44D}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b", "c", " "])
        #expect(terminal.character(of: terminal.screen[1][0]) == "\u{1F44D}")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }
}
