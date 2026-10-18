import Testing

@testable import TerminalCore

struct TerminalTests {
    @Test func startsWithABlankScreen() {
        let terminal = Terminal(columns: 4, rows: 2)
        #expect(lines(terminal) == ["    ", "    "])
    }

    @Test func printsCharacters() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("hé")
        #expect(lines(terminal) == ["hé  ", "    "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func printsWideCharactersInTwoCells() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("a中b")
        #expect(terminal.screen[0].map(\.width) == [1, 2, 0, 1, 1])
        #expect(lines(terminal) == ["a中 b "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 4))
    }

    @Test func waitsToWrapAfterAWideCharacterAtTheEnd() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("a中")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
        terminal.receive("b")
        #expect(lines(terminal) == ["a中 ", "b  "])
    }

    @Test func wrapsAWideCharacterThatDoesNotFit() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("ab中")
        #expect(lines(terminal) == ["ab ", "中  "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test func printsAWideCharacterInOneColumnScreen() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("中")
        #expect(terminal.screen[0].map(\.width) == [1])
    }

    @Test(arguments: [
        ("\u{1B}[1Gx", "x  ", [1, 1, 1]), ("\u{1B}[2Gx", " x ", [1, 1, 1]), ("\u{1B}[2G中", " 中 ", [1, 2, 0]),
    ])
    func clearsTheOtherHalfOfAWideCharacter(sequence: String, line: String, widths: [UInt8]) {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("中\(sequence)")
        #expect(lines(terminal) == [line])
        #expect(terminal.screen[0].map(\.width) == widths)
    }

    @Test func combinesMarksWithThePreviousCharacter() {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("e\u{301}x")
        #expect(lines(terminal) == ["éx "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func combinesMarksWithAWideCharacter() {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("❤\u{FE0F}中\u{FE0F}")
        #expect(terminal.screen[0].map(\.character) == ["❤\u{FE0F}", "中\u{FE0F}", " "])
    }

    @Test func combinesMarksWithTheLastCharacterOfALine() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("ae\u{301}")
        #expect(lines(terminal) == ["aé"])
    }

    @Test func ignoresMarksWithoutAPreviousCharacter() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{301}a\u{200B}")
        #expect(lines(terminal) == ["a "])
    }

    @Test func drawsLinesWithTheGraphicsCharacters() {
        var terminal = Terminal(columns: 5, rows: 3)
        terminal.receive("\u{1B}(0lqqqk\r\nx a x\r\nmqqqj\u{1B}(B")
        #expect(lines(terminal) == ["┌───┐", "│ ▒ │", "└───┘"])
    }

    @Test func restoresTheGraphicsCharactersWithTheCursor() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}(0\u{1B}7\u{1B}(B\u{1B}8q\u{1B}(B\u{1B}8q")
        #expect(lines(terminal) == ["─ "])
    }

    @Test func printsTheOtherCharactersInTheGraphicsSet() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}(0AZ^\u{1B}(Bq")
        #expect(lines(terminal) == ["AZ^q"])
    }

    @Test func wrapsAtTheEndOfALine() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcdef")
        #expect(lines(terminal) == ["abcd", "ef  "])
    }

    @Test func waitsForTheNextCharacterToWrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
        terminal.receive("\r\nef")
        #expect(lines(terminal) == ["abcd", "ef  "])
    }

    @Test func movesToANewLine() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\r\ncd")
        #expect(lines(terminal) == ["ab  ", "cd  "])
    }

    @Test func keepsTheColumnOnALineFeed() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\ncd")
        #expect(lines(terminal) == ["ab  ", "  cd"])
    }

    @Test func returnsToTheFirstColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc\rd")
        #expect(lines(terminal) == ["dbc ", "    "])
    }

    @Test func scrollsAtTheBottomOfTheScreen() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\r\ncd\r\nef")
        #expect(lines(terminal) == ["cd  ", "ef  "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test func scrollsWhenTheLastLineWraps() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcdefghij")
        #expect(lines(terminal) == ["efgh", "ij  "])
    }

    @Test func movesBackOnBackspace() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{8}c")
        #expect(lines(terminal) == ["ac  ", "    "])
    }

    @Test func stopsBackspaceAtTheFirstColumn() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{8}a")
        #expect(lines(terminal) == ["a   ", "    "])
    }

    @Test func cancelsThePendingWrapOnBackspace() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{8}e")
        #expect(lines(terminal) == ["abed", "    "])
    }

    @Test(arguments: ["\n", "\u{B}", "\u{C}"])
    func movesDownALine(character: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\(character)c")
        #expect(lines(terminal) == ["ab  ", "  c "])
    }

    @Test func repeatsThePrecedingCharacter() {
        var terminal = Terminal(columns: 6, rows: 2)
        terminal.receive("a\u{1B}[3b中\u{1B}[b")
        #expect(lines(terminal) == ["aaaa中 ", "中     "])
    }

    @Test func repeatsNothingBeforeACharacter() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[3bx")
        #expect(lines(terminal) == ["x   "])
    }

    @Test func erasesTheScrollback() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("a\r\nb\r\nc\u{1B}[3J")
        #expect(terminal.scrollback.isEmpty)
        #expect(terminal.removedScrollbackCount == 1)
        #expect(lines(terminal) == ["b ", "c "])
    }

    @Test func movesToTheNextTabStop() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb\tc")
        #expect(lines(terminal) == ["a       b       c   "])
    }

    @Test func stopsTabsAtTheLastColumn() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\t\ta")
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
        terminal.receive("\n\n\n\n    \u{1B}[2\(final)")
        #expect(terminal.cursor == position)
    }

    @Test func movesTheCursorOneStepByDefault() {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\u{1B}[B\u{1B}[0C")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func keepsTheCursorOnTheScreen() {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\u{1B}[99B\u{1B}[99C")
        #expect(terminal.cursor == Terminal.Position(row: 9, column: 9))
        terminal.receive("\u{1B}[99A\u{1B}[99D")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
    }

    @Test(arguments: [
        ("\u{1B}[3;5H", Terminal.Position(row: 2, column: 4)),
        ("\u{1B}[3;5f", Terminal.Position(row: 2, column: 4)),
        ("\u{1B}[H", Terminal.Position(row: 0, column: 0)),
        ("\u{1B}[3H", Terminal.Position(row: 2, column: 0)),
        ("\u{1B}[;5H", Terminal.Position(row: 0, column: 4)),
        ("\u{1B}[5G", Terminal.Position(row: 1, column: 4)),
        ("\u{1B}[5d", Terminal.Position(row: 4, column: 1)),
        ("\u{1B}[99;99H", Terminal.Position(row: 9, column: 9)),
    ])
    func movesTheCursorToAPosition(sequence: String, position: Terminal.Position) {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\n \(sequence)")
        #expect(terminal.cursor == position)
    }

    @Test(arguments: [
        ("\u{1B}[K", "ab  "),
        ("\u{1B}[0K", "ab  "),
        ("\u{1B}[1K", "   d"),
        ("\u{1B}[2K", "    "),
    ])
    func erasesInLine(sequence: String, line: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\r\nefgh\u{1B}[1;3H\(sequence)")
        #expect(lines(terminal) == [line, "efgh"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func cancelsThePendingWrapOnErase() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}[Ke")
        #expect(lines(terminal) == ["abce", "    "])
    }

    @Test(arguments: [
        ("\u{1B}[J", ["abcd", "e   ", "    "]),
        ("\u{1B}[0J", ["abcd", "e   ", "    "]),
        ("\u{1B}[1J", ["    ", "  gh", "ijkl"]),
        ("\u{1B}[2J", ["    ", "    ", "    "]),
    ])
    func erasesInDisplay(sequence: String, screen: [String]) {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("abcdefghijkl\u{1B}[2;2H\(sequence)")
        #expect(lines(terminal) == screen)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func ignoresTheTitle() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}]0;~/Developer — zsh\u{7}")
        #expect(lines(terminal) == ["    ", "    "])
    }

    @Test func growsTheScreen() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\r\ncd")
        terminal.resize(columns: 3, rows: 3)
        #expect(lines(terminal) == ["ab ", "cd ", "   "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func cutsLinesWhenTheScreenGetsNarrower() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("abcd")
        terminal.resize(columns: 2, rows: 1)
        #expect(lines(terminal) == ["ab"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test func keepsTheCursorLineWhenTheScreenGetsShorter() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a\r\nb\r\nc")
        terminal.resize(columns: 2, rows: 2)
        #expect(lines(terminal) == ["b ", "c "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func removesLinesBelowTheCursorWhenTheScreenGetsShorter() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a")
        terminal.resize(columns: 2, rows: 2)
        #expect(lines(terminal) == ["a ", "  "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test func restoresTheSavedCursor() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}7cd\r\n\u{1B}8x")
        #expect(lines(terminal) == ["abxd", "    "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
    }

    @Test func restoresTheSavedCursorWithAControlSequence() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[scd\r\n\u{1B}[ux")
        #expect(lines(terminal) == ["abxd", "    "])
    }

    @Test func restoresTheSavedStyle() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[1;31m\u{1B}7\u{1B}[m\u{1B}8a")
        #expect(terminal.screen[0][0].style == Terminal.Style(foreground: .indexed(1), isBold: true))
    }

    @Test func restoresThePendingWrap() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\u{1B}7\r\u{1B}8c")
        #expect(lines(terminal) == ["ab", "c "])
    }

    @Test func restoresTheHomePositionWithoutASave() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[1mab\r\n\u{1B}8x")
        #expect(lines(terminal) == ["xb  ", "    "])
        #expect(terminal.screen[0][0].style == Terminal.Style())
    }

    @Test func switchesToABlankAlternateScreen() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?1049h")
        #expect(lines(terminal) == ["    ", "    "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func restoresTheNormalScreenAndCursor() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?1049h\u{1B}[2;3Hxy\u{1B}[?1049lc")
        #expect(lines(terminal) == ["abc ", "    "])
    }

    @Test(arguments: [47, 1047])
    func switchesScreensWithoutTheCursor(mode: Int) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?\(mode)hx\u{1B}[?\(mode)lc")
        #expect(lines(terminal) == ["ab c", "    "])
    }

    @Test func clearsTheAlternateScreenWithTheBackgroundColor() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[44m\u{1B}[?1049h")
        #expect(terminal.screen[0].map(\.style.background) == [.indexed(4), .indexed(4)])
    }

    @Test func startsANewAlternateScreenEachTime() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1049hab\u{1B}[?1049l\u{1B}[?1049h")
        #expect(lines(terminal) == ["    "])
    }

    @Test func ignoresASecondSwitch() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("ab\u{1B}[?1049hx\u{1B}[?1049h\u{1B}[?1049l")
        #expect(lines(terminal) == ["ab  "])
    }

    @Test func resizesTheNormalScreenOnTheAlternateScreen() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}[?1049h")
        terminal.resize(columns: 2, rows: 3)
        terminal.receive("\u{1B}[?1049l")
        #expect(lines(terminal) == ["ab", "  ", "  "])
    }

    @Test func keepsASavedCursorForEachScreen() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?1049h\u{1B}[2;2H\u{1B}7\u{1B}[?1049lc")
        #expect(lines(terminal) == ["abc ", "    "])
    }

    @Test func keepsTheSavedCursorLineWhenTheNormalScreenGetsShorter() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[?1049h")
        terminal.resize(columns: 2, rows: 2)
        terminal.receive("\u{1B}[?1049l")
        #expect(lines(terminal) == ["b ", "c "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func scrollsUp() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[2S")
        #expect(lines(terminal) == ["c", "d", " ", " "])
        #expect(terminal.cursor == Terminal.Position(row: 3, column: 0))
    }

    @Test func scrollsDown() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[T")
        #expect(lines(terminal) == [" ", "a", "b", "c"])
    }

    @Test func scrollsNoMoreThanTheScreen() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("a\r\nb\u{1B}[9S")
        #expect(lines(terminal) == [" ", " "])
        terminal.receive("a\u{1B}[9T")
        #expect(lines(terminal) == [" ", " "])
    }

    @Test(arguments: ["S", "T"])
    func scrollsInLinesWithTheBackgroundColor(final: String) {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("\u{1B}[44m\u{1B}[2\(final)")
        #expect(terminal.screen.map { $0[0].style.background } == [.indexed(4), .indexed(4)])
    }

    @Test func scrollsInTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[2;3r")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
        terminal.receive("\u{1B}[3Hx\ny")
        #expect(lines(terminal) == ["a", "x", "y", "d"])
    }

    @Test func scrollsTheScrollRegionUpAndDown() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[2;3r\u{1B}[S")
        #expect(lines(terminal) == ["a", "c", " ", "d"])
        terminal.receive("\u{1B}[2T")
        #expect(lines(terminal) == ["a", " ", " ", "d"])
    }

    @Test func movesBelowTheScrollRegionWithoutScrolling() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[1;2r\u{1B}[3H\n\n")
        #expect(lines(terminal) == ["a", "b", "c", "d"])
        #expect(terminal.cursor == Terminal.Position(row: 3, column: 0))
    }

    @Test(arguments: ["\u{1B}[3;3r", "\u{1B}[3;2r", "\u{1B}[4;9r"])
    func ignoresAScrollRegionOfLessThanTwoLines(sequence: String) {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\u{1B}[4H\(sequence)\n")
        #expect(lines(terminal) == [" ", " ", " ", " "])
        #expect(terminal.cursor == Terminal.Position(row: 3, column: 0))
    }

    @Test func resetsTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("\u{1B}[2;3r\u{1B}[r\u{1B}[4Ha\n")
        #expect(lines(terminal) == [" ", " ", "a", " "])
    }

    @Test func resetsTheScrollRegionOnAResize() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("\u{1B}[2;3r")
        terminal.resize(columns: 1, rows: 3)
        terminal.receive("\u{1B}[3Ha\n")
        #expect(lines(terminal) == [" ", "a", " "])
    }

    @Test func indexesWithAnEscapeSequence() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\u{1B}Dc\u{1B}Ed")
        #expect(lines(terminal) == [" c", "d "])
    }

    @Test func movesUpWithAReverseIndex() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\r\nb\u{1B}Mc")
        #expect(lines(terminal) == ["c", "b", " "])
    }

    @Test func scrollsDownWithAReverseIndexAtTheTop() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[2;3r\u{1B}[2H\u{1B}Mx")
        #expect(lines(terminal) == ["a", "x", "b"])
    }

    @Test func staysOnTheFirstLineAboveTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\u{1B}[2;3r\u{1B}[1H\u{1B}Mx")
        #expect(lines(terminal) == ["x", " ", " "])
    }

    @Test func insertsLines() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[2H\u{1B}[2L")
        #expect(lines(terminal) == ["a", " ", " ", "b"])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test func deletesLines() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[2H\u{1B}[2M")
        #expect(lines(terminal) == ["a", "d", " ", " "])
    }

    @Test func insertsAndDeletesLinesInTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[1;3r\u{1B}[2H\u{1B}[L")
        #expect(lines(terminal) == ["a", " ", "b", "d"])
        terminal.receive("\u{1B}[M")
        #expect(lines(terminal) == ["a", "b", " ", "d"])
    }

    @Test func ignoresInsertedLinesOutsideTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 4)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[1;2r\u{1B}[4H\u{1B}[L\u{1B}[M")
        #expect(lines(terminal) == ["a", "b", "c", "d"])
    }

    @Test func movesToTheFirstColumnWhenItInsertsLines() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("abc\u{1B}[Lx")
        #expect(lines(terminal) == ["x  ", "abc"])
    }

    @Test func insertsCharacters() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("abcde\u{1B}[2G\u{1B}[2@x")
        #expect(lines(terminal) == ["ax bc"])
    }

    @Test func deletesCharacters() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("abcde\u{1B}[2G\u{1B}[2P")
        #expect(lines(terminal) == ["ade  "])
    }

    @Test func erasesCharacters() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("abcde\u{1B}[2G\u{1B}[2X")
        #expect(lines(terminal) == ["a  de"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test(arguments: ["@", "P", "X"])
    func changesNoMoreThanTheRestOfTheLine(final: String) {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("abc\u{1B}[2G\u{1B}[9\(final)")
        #expect(lines(terminal) == ["a  "])
    }

    @Test(arguments: ["@", "P", "X"])
    func changesCharactersWithTheBackgroundColor(final: String) {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("ab\u{1B}[G\u{1B}[44m\u{1B}[2\(final)")
        #expect(terminal.screen[0].map(\.style.background) == [.indexed(4), .indexed(4)])
    }

    @Test func reportsTheCursorPosition() {
        var terminal = Terminal(columns: 10, rows: 5)
        #expect(terminal.receive("\u{1B}[3;7H\u{1B}[6n") == "\u{1B}[3;7R")
        #expect(terminal.receive("\u{1B}[H\u{1B}[6n") == "\u{1B}[1;1R")
    }

    @Test func reportsTheStatus() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.receive("\u{1B}[5n") == "\u{1B}[0n")
    }

    @Test func repliesOnlyOnce() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1B}[5n")
        #expect(terminal.receive("a") == "")
    }

    @Test func ignoresUnknownStatusRequests() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.receive("\u{1B}[7n\u{1B}[?6n") == "")
    }

    @Test func reportsTheDeviceAttributes() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.receive("\u{1B}[c") == "\u{1B}[?1;2c")
        #expect(terminal.receive("\u{1B}[0c") == "\u{1B}[?1;2c")
        #expect(terminal.receive("\u{1B}[1c\u{1B}[>c") == "")
    }

    @Test func hidesAndShowsTheCursor() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.isCursorVisible)
        terminal.receive("\u{1B}[?25l")
        #expect(!terminal.isCursorVisible)
        terminal.receive("\u{1B}[?25h")
        #expect(terminal.isCursorVisible)
    }

    @Test func setsTheBracketedPasteMode() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(!terminal.usesBracketedPaste)
        terminal.receive("\u{1B}[?2004h")
        #expect(terminal.usesBracketedPaste)
        terminal.receive("\u{1B}[?2004l")
        #expect(!terminal.usesBracketedPaste)
    }

    @Test func setsTheApplicationCursorKeysMode() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(!terminal.usesApplicationCursorKeys)
        terminal.receive("\u{1B}[?1h")
        #expect(terminal.usesApplicationCursorKeys)
        terminal.receive("\u{1B}[?1l")
        #expect(!terminal.usesApplicationCursorKeys)
    }

    @Test func keepsTheLinesThatScrollOffTheScreen() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("a\r\nb\r\nc\r\nd")
        #expect(scrollback(terminal) == ["a", "b"])
        terminal.receive("\u{1B}[S")
        #expect(scrollback(terminal) == ["a", "b", "c"])
    }

    @Test func keepsNoLinesFromAScrollRegionBelowTheTop() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("\u{1B}[2;3r\u{1B}[3Ha\nb\n\u{1B}[S")
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func keepsTheLinesThatScrollOffAScrollRegionAtTheTop() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("\u{1B}[1;2r\u{1B}[2Ha\nb")
        #expect(scrollback(terminal) == [" "])
    }

    @Test func keepsNoLinesFromTheAlternateScreen() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("\u{1B}[?1049ha\r\nb\r\nc\u{1B}[S")
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func keepsNoDeletedLines() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("a\u{1B}[H\u{1B}[M")
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func keepsTheLinesThatAResizeRemoves() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\r\nb\r\nc")
        terminal.resize(columns: 1, rows: 1)
        #expect(scrollback(terminal) == ["a", "b"])
    }

    @Test func keepsTheNormalLinesThatAResizeRemovesOnTheAlternateScreen() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[?1049h")
        terminal.resize(columns: 1, rows: 1)
        #expect(scrollback(terminal) == ["a", "b"])
    }

    @Test func limitsTheScrollback() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive((1 ... 12_000).map { "\($0)\r\n" }.joined())
        #expect((10_000 ... 11_000).contains(terminal.scrollback.count))
        #expect(terminal.scrollback.count + terminal.removedScrollbackCount == 12_000)
        #expect(scrollback(terminal).last == "12000")
    }
}

private func lines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { String($0.map(\.character)) }
}

private func scrollback(_ terminal: Terminal) -> [String] {
    terminal.scrollback.map { String($0.map(\.character)) }
}
