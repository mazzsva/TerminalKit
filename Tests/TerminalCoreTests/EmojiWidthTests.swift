import Testing

@testable import TerminalCore

@Suite(.timeLimit(.minutes(1)))
struct EmojiWidthTests {
    static let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    static let heart = "\u{2764}\u{FE0F}"

    static let columnsAfterPrinting: [(String, Int)] = [
        (family, 2),
        ("\u{1F1FA}\u{1F1F8}", 2),
        ("\u{1F44D}\u{1F3FD}", 2),
        ("1\u{FE0F}\u{20E3}", 2),
        (heart, 2),
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

    @Test(
        arguments: [
            family, "\u{1F1FA}\u{1F1F8}", "\u{1F44D}\u{1F3FD}", "1\u{FE0F}\u{20E3}", heart,
            "\u{1F44D}\u{FE0F}\u{1F3FD}",
            "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", "\u{2764}\u{FE0F}\u{200D}\u{1F525}", "\u{1F9D1}\u{200D}\u{1F4BB}",
            "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}", "\u{261D}\u{1F3FD}",
        ])
    func placesAnEmojiSequenceInOneWideCell(text: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(text + "x")
        #expect(terminal.screen[0].prefix(3).map(\.width) == [2, 0, 1])
        #expect(terminal.character(of: terminal.screen[0][0]) == text)
        #expect(terminal.screen[0][2] == Terminal.Cell(scalar: "x"))
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
        #expect(terminal.cursor.column == 6)
    }

    @Test func keepsTwoEmojiInTwoCharacters() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1F600}\u{1F600}\(Self.heart)\(Self.heart)")
        #expect(terminal.screen[0].prefix(8).map(\.width) == [2, 0, 2, 0, 2, 0, 2, 0])
        #expect(terminal.cursor.column == 8)
    }

    @Test func placesASkinToneAfterACursorMoveAsItsOwnCharacter() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("abcdefgh\u{1B}[1;1H\u{1F44D}\u{1B}[1;3H\u{1F3FD}")
        #expect(terminal.screen[0].prefix(5).map(\.width) == [2, 0, 2, 0, 1])
        #expect(terminal.character(of: terminal.screen[0][0]) == "\u{1F44D}")
        #expect(terminal.character(of: terminal.screen[0][2]) == "\u{1F3FD}")
    }

    @Test func doesNotWidenAfterACursorMove() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{2764}x\u{1B}[1G\u{1B}[C\u{FE0F}")
        #expect(terminal.screen[0].prefix(2).map(\.width) == [1, 1])
    }

    @Test func widensAClusterInTheMiddleOfALineLikeAWideCharacter() {
        var emoji = Terminal(columns: 4, rows: 1)
        emoji.receive("a\u{4E2D}b\u{1B}[1G\(Self.heart)")
        var wide = Terminal(columns: 4, rows: 1)
        wide.receive("a\u{4E2D}b\u{1B}[1G\u{4E2D}")
        #expect(emoji.screen[0].map(\.width) == wide.screen[0].map(\.width))
        #expect(emoji.screen[0].dropFirst().map(emoji.character(of:)) == [" ", " ", "b"])
        #expect(emoji.cursor == wide.cursor)
    }

    @Test(arguments: [heart, "\u{1F1FA}\u{1F1F8}"])
    func wrapsAClusterThatWidensInTheLastColumn(text: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc" + text + "x")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b", "c", " "])
        #expect(terminal.screen[0][3] == .padding)
        #expect(terminal.screen[0].isWrapped)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == text)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 3))
    }

    @Test(arguments: [heart, "\u{1F1FA}\u{1F1F8}"])
    func wrapsAClusterThatWidensInTheLastColumnOfAScrollRegion(text: String) {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("\u{1B}[3;1Hzz\u{1B}[1;2r\u{1B}[2;1Habc" + text + "x")
        #expect(terminal.screen[0].isWrapped)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == text)
        #expect(terminal.screen[2].prefix(2).map(terminal.character(of:)) == ["z", "z"])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 3))
    }

    @Test func widensAClusterThatEndsAtTheLastColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab" + Self.heart)
        #expect(terminal.screen[0].map(\.width) == [1, 1, 2, 0])
        terminal.receive("x")
        #expect(terminal.character(of: terminal.screen[1][0]) == "x")
    }

    @Test func keepsAClusterInTheLastColumnWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labc" + Self.heart)
        #expect(terminal.screen[0].map(\.width) == [1, 1, 1, 1])
        #expect(terminal.character(of: terminal.screen[0][3]) == Self.heart)
        #expect(terminal.screen[1].allSatisfy { $0 == Terminal.Cell() })
    }

    @Test func insertsTheSecondCellOfAClusterInInsertMode() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("abc\u{1B}[1G\u{1B}[4h" + Self.heart)
        #expect(terminal.screen[0].prefix(5).map(\.width) == [2, 0, 1, 1, 1])
        #expect(terminal.screen[0].dropFirst(2).prefix(3).map(terminal.character(of:)) == ["a", "b", "c"])
        #expect(terminal.cursor.column == 2)
    }

    @Test func placesAFlagInAOneColumnScreen() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1F1FA}\u{1F1F8}")
        #expect(terminal.screen[0].map(\.width) == [1])
        #expect(terminal.character(of: terminal.screen[0][0]) == "\u{1F1FA}\u{1F1F8}")
    }

    @Test(arguments: [
        "\u{1B}[1G\u{1B}[@", "\u{1B}[1G\u{1B}[P", "\u{1B}[3G\u{1B}[1K", "\u{1B}[3Gy", "\u{1B}[2Gy", "\u{1B}[2X",
    ])
    func editsAClusterLikeAWideCharacter(edit: String) {
        var emoji = Terminal(columns: 6, rows: 1)
        emoji.receive("a\(Self.family)b\u{1B}[2G" + edit)
        var wide = Terminal(columns: 6, rows: 1)
        wide.receive("a\u{4E2D}b\u{1B}[2G" + edit)
        #expect(emoji.screen[0].map(\.width) == wide.screen[0].map(\.width))
        #expect(
            emoji.screen[0].map(emoji.character(of:)).map { $0 == Self.family ? "\u{4E2D}" : $0 }
                == wide.screen[0].map(wide.character(of:)))
        #expect(emoji.cursor == wide.cursor)
    }

    @Test func keepsAClusterWideThroughAReflow() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("ab\(Self.family)\r\nx")
        terminal.resize(columns: 3, rows: 3)
        #expect(terminal.screen[1].map(\.width) == [2, 0, 1])
        #expect(terminal.character(of: terminal.screen[1][0]) == Self.family)
    }

    @Test(arguments: ["\u{200D}", "\u{1F3FD}", "\u{FE0F}", "\u{20E3}", "\u{E0067}", "\u{200D}\u{200D}\u{1F469}"])
    func acceptsAJoinerWithNoBase(text: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive(text + "x\u{1B}[H" + text)
        #expect(terminal.cursor.row == 0)
    }

    @Test func limitsALongRunOfCombiningMarks() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("e" + String(repeating: "\u{301}", count: 100_000) + "x")
        #expect(terminal.character(of: terminal.screen[0][0]).utf8.count <= 1_024)
        #expect(terminal.screen[0][1] == Terminal.Cell(scalar: "x"))
    }

    @Test func limitsALongJoinedSequence() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1F468}" + String(repeating: "\u{200D}\u{1F468}", count: 20_000))
        #expect(terminal.screen[0].prefix(2).map(\.width) == [2, 0])
        #expect(terminal.character(of: terminal.screen[0][0]).utf8.count <= 1_024)
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
