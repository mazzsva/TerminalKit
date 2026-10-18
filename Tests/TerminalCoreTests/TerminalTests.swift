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

    @Test(arguments: [
        ("中\r\u{1B}[Px", "x   "), ("中\r\u{1B}[P", "    "), ("中\u{1B}[D\u{1B}[@", "    "), ("ab中\r\u{1B}[@", " ab "),
        ("中\u{1B}[D\u{1B}[X", "    "), ("中\r\u{1B}[X", "    "), ("中\u{1B}[D\u{1B}[K", "    "),
    ])
    func blanksTheOtherHalfOfABrokenWideCharacter(text: String, line: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive(text)
        #expect(lines(terminal) == [line])
        #expect(terminal.screen[0].map(\.width) == [1, 1, 1, 1])
    }

    @Test func blanksAWideCharacterThatAResizeCuts() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1049hab中")
        terminal.resize(columns: 3, rows: 1)
        #expect(lines(terminal) == ["ab "])
        #expect(terminal.screen[0].map(\.width) == [1, 1, 1])
    }

    @Test func marksTheLinesThatWrap() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("abcdef\r\ngh")
        #expect(terminal.screen.map(\.isWrapped) == [true, false, false])
    }

    @Test func keepsTheEndOfAWrappedLineInTheScrollback() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("ab  cd\r\nx")
        #expect(scrollback(terminal) == ["ab  ", "cd"])
        #expect(terminal.scrollback.map(\.isWrapped) == [true, false])
    }

    @Test(arguments: [
        ("\r\u{1B}[J", "the screen below it is erased"), ("\u{1B}[A\u{1B}[K", "the end of the line is erased"),
        ("\u{1B}[L", "a line is inserted after it"), ("\u{1B}[M", "the next line is deleted"),
        ("\u{1B}[2;3r\u{1B}[T", "the region below it scrolls down"),
    ])
    func unwrapsALineWhenItsContinuationChanges(sequence: String, reason: String) {
        var terminal = Terminal(columns: 5, rows: 4)
        terminal.receive("AAAAABB\(sequence)")
        #expect(!terminal.screen[0].isWrapped, "\(reason)")
    }

    @Test(arguments: ["\u{1B}[H\u{1B}[2J", "\u{1B}[1J", "\u{1B}[T", "\u{1B}[H\u{1B}[M"])
    func unwrapsTheScrollbackWhenTheFirstLineChanges(sequence: String) {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("AAAAABBB\(sequence)")
        #expect(terminal.scrollback.map(\.isWrapped) == [false])
    }

    @Test func marksALineThatWrapsAtTheBottomOfARegion() {
        var terminal = Terminal(columns: 5, rows: 5)
        terminal.receive("\u{1B}[1;4r\u{1B}[4HAAAAABB")
        #expect(terminal.screen.map(\.isWrapped) == [false, false, true, false, false])
    }

    @Test func marksNoLineThatCannotMoveDown() {
        var terminal = Terminal(columns: 5, rows: 3)
        terminal.receive("\u{1B}[1;2r\u{1B}[3HAAAAABB")
        #expect(terminal.screen.map(\.isWrapped) == [false, false, false])
    }

    @Test func marksALineThatWrapsIntoTheScrollback() {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("ab cd")
        #expect(scrollback(terminal) == ["ab "])
        #expect(terminal.scrollback.map(\.isWrapped) == [true])
    }

    @Test func unwrapsTheScrollbackOnAReset() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive(String(repeating: "A", count: 25) + "\u{1B}c")
        #expect(terminal.scrollback.last?.isWrapped == false)
    }

    @Test func keepsTheWrapThatZshMakes() {
        var terminal = Terminal(columns: 5, rows: 2)
        terminal.receive("abcde \r\u{1B}[Kf")
        #expect(terminal.screen.map(\.isWrapped) == [true, false])
    }

    @Test func unwrapsTheLastLineOfARegionThatScrollsUp() {
        var terminal = Terminal(columns: 5, rows: 4)
        terminal.receive("\u{1B}[3HAAAAABB\u{1B}[2;3r\u{1B}[S")
        #expect(terminal.screen.map(\.isWrapped) == [false, false, false, false])
    }

    @Test func unwrapsTheLastLineOfARegionThatScrollsDown() {
        var terminal = Terminal(columns: 5, rows: 4)
        terminal.receive("\u{1B}[2HAAAAABB\u{1B}[2;3r\u{1B}[T")
        #expect(terminal.screen.map(\.isWrapped) == [false, false, false, false])
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

    @Test(arguments: [
        "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
        "1\u{FE0F}\u{20E3}",
        "น\u{E49}\u{E33}",
        "\u{1100}\u{1161}\u{11A8}",
        "क\u{94D}ष\u{93F}",
        "a" + String(repeating: "\u{301}", count: 15),
    ])
    func keepsEveryScalarOfACluster(cluster: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive(cluster)
        let cells = terminal.screen[0].filter { $0.width > 0 && !$0.isBlank }
        #expect(String(cells.map(\.character)) == cluster)
    }

    @Test func dropsTheMarksAfterSixteenScalars() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("a" + String(repeating: "\u{301}", count: 50_000) + "b")
        #expect(terminal.screen[0][0].character.unicodeScalars.count == 16)
        #expect(terminal.screen[0][1].character == "b")
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

    @Test(arguments: [(4, 3, "a"), (5, 2, "中"), (1, 3, "中"), (7, 1, "x"), (3, 4, "é")])
    func repeatsLikePrintingTheCharacter(columns: Int, rows: Int, character: String) {
        for start in ["", "\u{1B}[2;3H", "\u{1B}[2;3r\u{1B}[1;2H", "\u{1B}[?7l", "\u{1B}[4h\u{1B}[1;2H"] {
            for count in [1, 9, 10, 11, 23, 64, 1_000] {
                var repeated = Terminal(columns: columns, rows: rows)
                var printed = repeated
                repeated.receive("\(start)zz\u{1B}[\(rows);1Hyy\u{1B}[H\(start)\(character)\u{1B}[\(count)b")
                printed.receive(
                    "\(start)zz\u{1B}[\(rows);1Hyy\u{1B}[H\(start)" + String(repeating: character, count: count + 1)
                )
                #expect(lines(repeated) == lines(printed))
                #expect(repeated.screen.map(\.isWrapped) == printed.screen.map(\.isWrapped))
                #expect(repeated.cursor == printed.cursor)
                repeated.receive("w")
                printed.receive("w")
                #expect(lines(repeated) == lines(printed))
            }
        }
    }

    @Test func repeatsAtMostAScreen() {
        var terminal = Terminal(columns: 80, rows: 24)
        terminal.receive("a" + String(repeating: "\u{1B}[65535b", count: 200))
        #expect(terminal.removedScrollbackCount == 0)
        #expect(terminal.scrollback.count < 6_000)
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

    @Test func overwritesTheLastColumnWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labcdef\u{1B}[?7hgh")
        #expect(lines(terminal) == ["abcg", "h   "])
    }

    @Test func keepsAWideCharacterOnTheLineWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labc中")
        #expect(lines(terminal) == ["ab中 ", "    "])
    }

    @Test func insertsCharactersInInsertMode() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("abc\r\u{1B}[4hxy\u{1B}[4lz")
        #expect(lines(terminal) == ["xyzbc "])
    }

    @Test func keepsReplaceModeForOtherModes() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("abc\r\u{1B}[20hx")
        #expect(lines(terminal) == ["xbc "])
    }

    @Test func resetsTheTerminal() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("a\r\nb\r\nc\u{1B}[?1h\u{1B}[?2004h\u{1B}[?25l\u{1B}[?1004h\u{1B}[?1049h\u{1B}[1mx\u{1B}c")
        #expect(lines(terminal) == ["    ", "    "])
        #expect(scrollback(terminal) == ["a"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
        #expect(!terminal.usesApplicationCursorKeys)
        #expect(!terminal.usesBracketedPaste)
        #expect(terminal.isCursorVisible)
        #expect(!terminal.usesFocusReporting)
        terminal.receive("y")
        #expect(terminal.screen[0][0].style == Terminal.Style())
    }

    @Test func repliesBeforeAReset() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[6n\u{1B}c") == "\u{1B}[1;1R")
    }

    @Test func keepsAPartialCharacterAcrossAReset() {
        var terminal = Terminal(columns: 4, rows: 1)
        _ = terminal.receive([0x1B, 0x63, 0xC3])
        _ = terminal.receive([0xA9])
        #expect(lines(terminal) == ["é   "])
    }

    @Test func movesToTheNextTabStop() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb\tc")
        #expect(lines(terminal) == ["a       b       c   "])
    }

    @Test func setsATabStop() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("\u{1B}[3g\u{1B}[5G\u{1B}H\r\tx\ty")
        #expect(lines(terminal) == ["    x              y"])
    }

    @Test func clearsATabStop() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("\u{1B}[9G\u{1B}[g\r\tx")
        #expect(lines(terminal) == ["                x   "])
    }

    @Test func movesByTabStops() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("\u{1B}[2Ix\u{1B}[2Zy\u{1B}[3Zz")
        #expect(lines(terminal) == ["z       y       x   "])
    }

    @Test func addsTabStopsToNewColumns() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}[3g")
        terminal.resize(columns: 20, rows: 1)
        terminal.receive("\tx")
        #expect(lines(terminal) == ["                x   "])
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

    @Test(arguments: [
        ("A", 3, 1), ("A", 1, 1), ("A", 5, 1), ("A", 0, 0),
        ("B", 2, 4), ("B", 4, 4), ("B", 0, 4), ("B", 5, 5),
        ("F", 3, 1), ("F", 5, 1), ("F", 0, 0),
        ("E", 2, 4), ("E", 0, 4), ("E", 5, 5),
    ])
    func stopsTheCursorAtTheMarginsOfTheScrollRegion(final: String, row: Int, stop: Int) {
        var terminal = Terminal(columns: 10, rows: 6)
        terminal.receive("\u{1B}[2;5r\u{1B}[\(row + 1);3H\u{1B}[10\(final)")
        #expect(terminal.cursor.row == stop)
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

    @Test(arguments: ["0", "2"])
    func setsTheTitle(command: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}]\(command);~/Developer — zsh\u{7}")
        #expect(terminal.title == "~/Developer — zsh")
        #expect(lines(terminal) == ["    ", "    "])
    }

    @Test func ignoresOtherOperatingSystemCommands() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}]1;Icon\u{7}\u{1B}]7;file:///tmp\u{7}\u{1B}]2\u{7}")
        #expect(terminal.title.isEmpty)
    }

    @Test func keepsTheTitleAfterAReset() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}]2;vim\u{7}\u{1B}c")
        #expect(terminal.title == "vim")
    }

    @Test func growsTheScreen() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\r\ncd")
        terminal.resize(columns: 3, rows: 3)
        #expect(lines(terminal) == ["ab ", "cd ", "   "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test func reflowsLinesWhenTheScreenGetsNarrower() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\r\n")
        terminal.resize(columns: 2, rows: 2)
        #expect(scrollback(terminal) == ["ab"])
        #expect(lines(terminal) == ["cd", "  "])
        terminal.receive("e")
        #expect(lines(terminal) == ["cd", "e "])
    }

    @Test func reflowsLinesWhenTheScreenGetsWider() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("abcde\r\n")
        terminal.resize(columns: 6, rows: 3)
        #expect(terminal.scrollback.isEmpty)
        #expect(lines(terminal) == ["abcde ", "      ", "      "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test func reflowsTheScrollbackBack() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("ab  cdef\r\n$")
        terminal.resize(columns: 3, rows: 1)
        terminal.resize(columns: 6, rows: 1)
        #expect(scrollback(terminal) == ["ab  cd", "ef"])
        #expect(lines(terminal) == ["$     "])
    }

    @Test func keepsAClearedScreen() {
        var terminal = Terminal(columns: 10, rows: 4)
        terminal.receive((0 ..< 8).map { "line\($0)\r\n" }.joined() + "\u{1B}[H\u{1B}[2J$ ")
        let scrollbackCount = terminal.scrollback.count
        terminal.resize(columns: 12, rows: 4)
        #expect(terminal.scrollback.count == scrollbackCount)
        #expect(lines(terminal).first == "$           ")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func keepsThePromptApartFromOldOutput() {
        var terminal = Terminal(columns: 5, rows: 2)
        terminal.receive("$ cmd\r\nAAAAABBB\r\n\u{1B}[H\u{1B}[2J$ ")
        terminal.resize(columns: 10, rows: 2)
        #expect(scrollback(terminal).last == "AAAAA")
        #expect(lines(terminal).first == "$         ")
    }

    @Test func movesAWideCharacterThatDoesNotFitToTheNextLine() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abc中\r\n")
        terminal.resize(columns: 6, rows: 2)
        #expect(lines(terminal) == ["abc中  ", "      "])
        terminal.resize(columns: 4, rows: 2)
        #expect(scrollback(terminal) == ["abc "])
        #expect(lines(terminal) == ["中   ", "    "])
    }

    @Test func keepsTheWrappedLinesWhenOnlyTheRowsChange() {
        var terminal = Terminal(columns: 3, rows: 3)
        terminal.receive("abcdef")
        terminal.resize(columns: 3, rows: 2)
        #expect(terminal.screen.map(\.isWrapped) == [true, false])
    }

    @Test func keepsASpaceBeforeAWideCharacterThatWraps() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("中 😀\r\n")
        terminal.resize(columns: 2, rows: 3)
        terminal.resize(columns: 6, rows: 3)
        #expect(lines(terminal).first == "中  😀  ")
    }

    @Test func keepsAPositionOnTheSecondHalfOfAWideCharacter() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("abcdefgh中")
        let (lines, positions) = Terminal.reflow(
            terminal.screen,
            columns: 1,
            positions: [Terminal.Position(row: 0, column: 9)]
        )
        #expect(lines.count == 9)
        #expect(positions == [Terminal.Position(row: 8, column: 0)])
    }

    @Test func keepsTheCursorLineForTheShell() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("$ echo 0123456789")
        terminal.resize(columns: 5, rows: 3)
        #expect(lines(terminal) == ["$ ech", "34567", "     "])
        #expect(terminal.screen.map(\.isWrapped) == [false, false, false])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 4))
    }

    @Test(arguments: [(3, "\u{1B}[?47h"), (2, "\u{1B}[?1047h")])
    func resizesTheAlternateScreenAfterTheRowsChange(rows: Int, sequence: String) {
        var terminal = Terminal(columns: 4, rows: rows)
        terminal.receive("\u{1B}[\(rows)H\u{1B}7\u{1B}[H")
        terminal.resize(columns: 4, rows: 1)
        terminal.receive(sequence)
        terminal.resize(columns: 5, rows: 1)
        #expect(terminal.screen.map(\.count) == [5])
    }

    @Test func reflowsTheNormalScreenAroundItsCursor() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("aaaaaaaa\r\nbbbbbbbb\r\n$ \u{1B}[?1047h")
        terminal.resize(columns: 4, rows: 3)
        terminal.receive("\u{1B}[?1047l")
        #expect(scrollback(terminal) == ["aaaa", "aaaa"])
        #expect(lines(terminal) == ["bbbb", "bbbb", "$   "])
    }

    @Test func keepsTheCursorLineOfTheNormalScreenWhenTheRowsChange() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[?1047h")
        terminal.resize(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1047l")
        #expect(scrollback(terminal) == ["a", "b"])
        #expect(lines(terminal) == ["c   "])
    }

    @Test func movesTheSavedCursorWhenTheRowsChange() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("a\r\nb\u{1B}7\r\nc")
        terminal.resize(columns: 4, rows: 2)
        terminal.receive("\u{1B}8X")
        #expect(lines(terminal) == ["bX  ", "c   "])
    }

    @Test func keepsThePendingWrapWhenTheRowsChange() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("abcd")
        terminal.resize(columns: 4, rows: 2)
        terminal.receive("e")
        #expect(lines(terminal) == ["abcd", "e   "])
    }

    @Test func reflowsTheScrollbackOfTheCursorLine() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive(String(repeating: "J", count: 45) + "$ ")
        terminal.resize(columns: 5, rows: 3)
        #expect(scrollback(terminal) == Array(repeating: "JJJJJ", count: 4))
    }

    @Test func keepsTheSavedCursorOnItsCharacter() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("0123456789abc\u{1B}7\r\n")
        terminal.resize(columns: 5, rows: 3)
        terminal.receive("\u{1B}8X")
        #expect(lines(terminal) == ["56789", "abcX ", "     "])
    }

    @Test func cancelsThePendingWrapOnTheAlternateScreen() {
        var terminal = Terminal(columns: 5, rows: 3)
        terminal.receive("\u{1B}[?1049habcde")
        terminal.resize(columns: 8, rows: 3)
        terminal.receive("f")
        #expect(lines(terminal).first == "abcdf   ")
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

    @Test(arguments: [(8, ["abcX    ", "        ", "        "]), (2, ["aX", "  ", "  "])])
    func cancelsTheSavedPendingWrapOnTheAlternateScreen(columns: Int, lines expected: [String]) {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("\u{1B}[?1049habcd\u{1B}7")
        terminal.resize(columns: columns, rows: 3)
        terminal.receive("\u{1B}8X")
        #expect(lines(terminal) == expected)
    }

    @Test func keepsTheSavedPendingWrapOnTheAlternateScreenWhenTheRowsChange() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("\u{1B}[?1049habcd\u{1B}7")
        terminal.resize(columns: 4, rows: 2)
        terminal.receive("\u{1B}8X")
        #expect(lines(terminal) == ["abcd", "X   "])
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
        terminal.receive("abcd\r\n\u{1B}[?1049h")
        terminal.resize(columns: 2, rows: 3)
        terminal.receive("\u{1B}[?1049l")
        #expect(lines(terminal) == ["ab", "cd", "  "])
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

    @Test func countsTheBells() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a\u{7}b\u{7}\u{7}")
        #expect(terminal.bellCount == 3)
        #expect(terminal.screen[0].prefix(2).map(\.character) == ["a", "b"])
    }

    @Test(arguments: ["\u{1B}]0;title\u{7}", "\u{1B}P1;2\u{7}x\u{1B}\\", "\u{1B}_\u{7}\u{1B}\\"])
    func ignoresABellInAString(string: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive(string)
        #expect(terminal.bellCount == 0)
    }

    @Test func keepsTheBellCountAfterAReset() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{7}\u{1B}c\u{7}")
        #expect(terminal.bellCount == 2)
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

    @Test(arguments: [
        ("0", Terminal.CursorShape.block), ("", .block), ("1", .block), ("2", .block), ("3", .underline),
        ("4", .underline), ("5", .bar), ("6", .bar),
    ])
    func setsTheCursorShape(parameter: String, shape: Terminal.CursorShape) {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1B}[5 q\u{1B}[3 q\u{1B}[\(parameter) q")
        #expect(terminal.cursorShape == shape)
    }

    @Test(arguments: ["\u{1B}[7 q", "\u{1B}[?2 q", "\u{1B}[2q", "\u{1B}[2!q", "\u{1B}[2 p"])
    func ignoresOtherCursorShapeSequences(sequence: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[5 q" + sequence + "x")
        #expect(terminal.cursorShape == .bar)
        #expect(terminal.screen[0][0].character == "x")
    }

    @Test func keepsTheCursorShapeOnTheAlternateScreen() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1B}[5 q\u{1B}[?1049h")
        #expect(terminal.cursorShape == .bar)
        terminal.receive("\u{1B}[3 q\u{1B}[?1049l")
        #expect(terminal.cursorShape == .underline)
    }

    @Test func resetsTheCursorShape() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1B}[5 q\u{1B}c")
        #expect(terminal.cursorShape == .block)
    }

    @Test func setsTheFocusReportingMode() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(!terminal.usesFocusReporting)
        terminal.receive("\u{1B}[?1004h")
        #expect(terminal.usesFocusReporting)
        terminal.receive("\u{1B}[?1049h\u{1B}[?1049l")
        #expect(terminal.usesFocusReporting)
        terminal.receive("\u{1B}[?1004l")
        #expect(!terminal.usesFocusReporting)
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

    @Test func keepsTheScrollbackWithoutBlankCellsAtTheEnd() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("ab\r\n\u{1B}[41m \u{1B}[m\r\nabcd\r\n")
        #expect(terminal.scrollback.map(\.count) == [2, 1, 4])
    }

    @Test func keepsTheLinesThatScrollOffAScrollRegionAtTheTop() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("\u{1B}[1;2r\u{1B}[2Ha\nb")
        #expect(scrollback(terminal) == [""])
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
