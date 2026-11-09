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

    @Test func keepsTheCellsPastTheColumnsOnTheAlternateScreen() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1049hab中")
        terminal.resize(columns: 3, rows: 1)
        terminal.resize(columns: 4, rows: 1)
        #expect(terminal.character(of: terminal.screen[0][2]) == "中")
        #expect(terminal.screen[0].map(\.width) == [1, 1, 2, 0])
    }

    @Test func movesTheCellsPastTheColumnsWhenItErases() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("\u{1B}[?1049habcdef")
        terminal.resize(columns: 3, rows: 1)
        terminal.receive("\u{1B}[2G\u{1B}[K")
        terminal.resize(columns: 6, rows: 1)
        #expect(lines(terminal) == ["adef  "])
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

    @Test(arguments: ["\u{1B}[1J", "\u{1B}[T"])
    func unwrapsTheScrollbackWhenTheFirstLineChanges(sequence: String) {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("AAAAABBB\(sequence)")
        #expect(terminal.scrollback.map(\.isWrapped) == [false])
    }

    @Test(arguments: ["\u{1B}[H\u{1B}[2J", "\u{1B}[H\u{1B}[M"])
    func keepsTheWrapWhenTheFirstLineMovesToTheScrollback(sequence: String) {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive("AAAAABBB\(sequence)")
        #expect(terminal.scrollback.map(\.isWrapped) == [true, false])
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
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["❤\u{FE0F}", "中\u{FE0F}", " "])
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
        #expect(cells.map(terminal.character(of:)).joined() == cluster)
    }

    @Test func dropsTheMarksAfterTheByteLimit() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("a" + String(repeating: "\u{301}", count: 50_000) + "b")
        #expect(terminal.character(of: terminal.screen[0][0]).utf8.count == 1_023)
        #expect(terminal.character(of: terminal.screen[0][1]) == "b")
    }

    @Test func dropsAMarkWithoutAPreviousCharacter() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{301}a\u{301}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a\u{301}", " "])
    }

    @Test func placesEachSpacingMarkInItsOwnCell() {
        var terminal = Terminal(columns: 6, rows: 1)
        terminal.receive("\u{1019}\u{103C}\u{1014}\u{103A}\u{1019}\u{102C}\u{1038}")
        #expect(
            terminal.screen[0].map(terminal.character(of:)) == [
                "\u{1019}", "\u{103C}", "\u{1014}\u{103A}", "\u{1019}", "\u{102C}", "\u{1038}",
            ])
    }

    @Test func combinesAMarkWithASpacingMarkInItsOwnCell() {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("\u{1015}\u{102B}\u{103A}")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["\u{1015}", "\u{102B}\u{103A}", " "])
    }

    @Test(arguments: ["\u{915}\u{93E}", "\u{B95}\u{BC6}\u{BBE}"])
    func keepsSpacingMarksThatJoinInOtherTerminalsInTheirOwnCells(character: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive(character)
        #expect(terminal.cursor.column == character.unicodeScalars.count)
    }

    @Test func keepsMarksThatDoNotJoinAsOneCharacterInOneCell() {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("a\u{1160}\u{2066}x")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a\u{1160}\u{2066}", "x", " "])
    }

    @Test func keepsASpacingMarkWithoutAPreviousCharacter() {
        var terminal = Terminal(columns: 3, rows: 1)
        terminal.receive("\u{93E}x")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["\u{93E}", "x", " "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
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

    @Test(arguments: ["A", "1"])
    func endsTheGraphicsCharactersWithAnyOtherCharacterSet(final: String) {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}(0q\u{1B}(\(final)q")
        #expect(lines(terminal) == ["─q"])
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

    @Test func erasesTheScrollback() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("a\r\nb\r\nc\u{1B}[3J")
        #expect(terminal.scrollback.isEmpty)
        #expect(terminal.removedScrollbackCount == 1)
        #expect(lines(terminal) == ["b ", "c "])
    }

    @Test func clearsToStart() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a\r\nb\r\nc\r\nd\u{1B}[2H")
        terminal.clearToStart()
        #expect(terminal.scrollback.isEmpty)
        #expect(terminal.removedScrollbackCount == 2)
        #expect(lines(terminal) == ["c ", "d ", "  "])
    }

    @Test func movesTheCursorLineToTheTopWhenClearingToStart() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[1;2r\u{1B}[3;2H")
        terminal.clearToStart()
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
        #expect(lines(terminal) == ["c ", "  ", "  "])
    }

    @Test func keepsTheRemovedScrollbackCountAfterAReset() {
        var terminal = Terminal(columns: 20, rows: 2)
        terminal.receive("1\r\n2\r\n3\r\n4\u{1B}[3J5\r\n6\r\n7\u{1B}c")
        #expect(terminal.removedScrollbackCount == 2)
    }

    @Test func overwritesTheLastColumnWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labcdef\u{1B}[?7hgh")
        #expect(lines(terminal) == ["abcg", "h   "])
    }

    @Test func dropsAWideCharacterThatDoesNotFitWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labc中")
        #expect(lines(terminal) == ["abc ", "    "])
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

    @Test func switchesToReverseVideo() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?5h")
        #expect(terminal.usesReverseVideo)
        terminal.receive("\u{1B}[?5l")
        #expect(!terminal.usesReverseVideo)
    }

    @Test func resetsTheTerminal() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive(
            "a\r\nb\r\nc\u{1B}[?1h\u{1B}[?2004h\u{1B}[?25l\u{1B}[?1004h\u{1B}[?5h\u{1B}[?1049h\u{1B}[1mx\u{1B}c")
        #expect(lines(terminal) == ["    ", "    "])
        #expect(scrollback(terminal) == ["a"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
        #expect(!terminal.usesApplicationCursorKeys)
        #expect(!terminal.usesBracketedPaste)
        #expect(terminal.isCursorVisible)
        #expect(!terminal.usesFocusReporting)
        #expect(!terminal.usesReverseVideo)
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

    @Test func softResetsTheModes() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1h\u{1B}[?25l\u{1B}[5 q\u{1B}[?5h\u{1B}[!p")
        #expect(!terminal.usesApplicationCursorKeys)
        #expect(terminal.isCursorVisible)
        #expect(terminal.cursorShape == .block)
        #expect(!terminal.usesReverseVideo)
    }

    @Test func softResetsInsertMode() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("abc\r\u{1B}[4h\u{1B}[!px")
        #expect(lines(terminal) == ["xbc "])
    }

    @Test(arguments: ["\u{1B}[!p", "\u{1B}c"])
    func keepsAutowrapOffAfterAReset(reset: String) {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("\u{1B}[?7l\(reset)abc")
        #expect(lines(terminal) == ["ab", "  "])
    }

    @Test(arguments: ["\n", "\u{B}", "\u{C}"])
    func returnsToTheFirstColumnInNewLineMode(lineFeed: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[20hab\(lineFeed)")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
        terminal.receive("\u{1B}[20l\u{1B}[Hab\(lineFeed)")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test(arguments: ["\u{1B}[!p", "\u{1B}c"])
    func resetsNewLineMode(reset: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[20h\(reset)ab\n")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test func softResetsTheTabStops() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("\u{1B}[3g\u{1B}[!p\t")
        #expect(terminal.cursor.column == 8)
    }

    @Test func shiftsBetweenCharacterSets() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B})0q\u{E}q\u{F}q")
        #expect(lines(terminal) == ["q─q "])
    }

    @Test(arguments: [("*", "n"), ("+", "o")])
    func locksTheOtherCharacterSets(designator: String, shift: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}\(designator)0\u{1B}\(shift)q")
        #expect(lines(terminal) == ["─   "])
    }

    @Test(arguments: [
        ("A", "#", "£"), ("K", "~", "ß"), ("4", "@", "¾"), ("Z", "[", "¡"), ("1", "q", "q"), ("U", "q", "q"),
    ])
    func translatesWithEachCharacterSet(final: String, input: String, output: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}(\(final)\(input)")
        #expect(lines(terminal) == [output + "   "])
    }

    @Test func savesTheCharacterSetsButNotTheShift() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B})0\u{E}\u{1B}7\u{F}\u{1B})B\u{1B}8q\u{E}q")
        #expect(lines(terminal) == ["q─  "])
    }

    @Test func keepsAnUnderscoreInLineDrawing() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}(0_")
        #expect(lines(terminal) == ["_   "])
    }

    @Test func fillsTheScreenWithoutMovingTheCursor() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("\u{1B}[41m\u{1B}[2;2H\u{1B}#8")
        #expect(lines(terminal) == ["EE", "EE"])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
        #expect(terminal.screen[0][0].style == Terminal.Style())
    }

    @Test func softResetsTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("1\r\n2\r\n3\u{1B}[1;2r\u{1B}[!p\u{1B}[3H\nX")
        #expect(lines(terminal) == ["2", "3", "X"])
    }

    @Test func softResetsTheStyle() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[1;7;31m\u{1B}[!pa")
        #expect(terminal.screen[0][0].style == Terminal.Style())
    }

    @Test func softResetsTheGraphicsCharacters() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}(0\u{1B}[!pq")
        #expect(lines(terminal) == ["q   "])
    }

    @Test func softResetsTheSavedCursor() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[1m\u{1B}(0\u{1B}7\u{1B}[!p\u{1B}[4m\u{1B}(0\r\n\u{1B}8xq")
        #expect(lines(terminal) == ["xq  ", "    "])
        #expect(terminal.screen[0][0].style == Terminal.Style())
    }

    @Test func keepsTheScreenOnASoftReset() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("a\r\nb\r\nc\u{1B}[!p")
        #expect(lines(terminal) == ["b   ", "c   "])
        #expect(scrollback(terminal) == ["a"])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
        terminal.receive("\u{1B}[?1049h\u{1B}[>1u\u{1B}[!p")
        #expect(terminal.isAlternateScreenActive)
        #expect(terminal.usesDisambiguatedKeys)
    }

    @Test func keepsATabInTheText() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb")
        #expect(terminal.screen[0].filter(\.isText).map(terminal.character(of:)).joined().hasPrefix("a\tb"))
        #expect(terminal.screen[0][1 ... 7].allSatisfy { !$0.isText || terminal.character(of: $0) == "\t" })
    }

    @Test(arguments: ["\u{1B}[3Gx", "\u{1B}[4G\u{1B}[X", "\u{1B}[4G\u{1B}[P", "\u{1B}[2G\u{1B}[P", "\u{1B}[4G\u{1B}[@"])
    func replacesATabWithSpacesWhenAPartChanges(change: String) {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb" + change)
        #expect(!terminal.screen[0].contains { terminal.character(of: $0) == "\t" })
        #expect(terminal.screen[0][1].isWritten)
    }

    @Test func keepsATabWithAMarkAtItsEnd() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\t\u{301}b")
        #expect(terminal.character(of: terminal.screen[0][1]) == "\t")
        #expect(terminal.cursor.column == 9)
    }

    @Test(arguments: ["\u{1B}[4G", "\u{1B}[3G"])
    func replacesATabWithSpacesForAMarkInside(move: String) {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb" + move + "\u{301}")
        #expect(!terminal.screen[0].contains { terminal.character(of: $0) == "\t" })
    }

    @Test func replacesATabThatInsertedCellsCut() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("x\u{1B}[3G\t\u{1B}[G\u{1B}[7@")
        #expect(!terminal.screen[0].contains { terminal.character(of: $0) == "\t" })
    }

    @Test func keepsATabThatMovesAsAWhole() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb\u{1B}[2G\u{1B}[@")
        #expect(terminal.character(of: terminal.screen[0][2]) == "\t")
    }

    @Test func movesOverTextWithoutATab() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("abc\r\t")
        #expect(!terminal.screen[0].contains { terminal.character(of: $0) == "\t" })
    }

    @Test func keepsATabThroughTheScrollback() {
        var terminal = Terminal(columns: 20, rows: 1)
        terminal.receive("a\tb\r\n")
        #expect(terminal.character(of: terminal.scrollback[0][1]) == "\t")
    }

    @Test func movesATabThatDoesNotFitToTheNextRow() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.receive("abcdef\tb\r\nx")
        terminal.resize(columns: 7, rows: 3)
        #expect(terminal.screen[0].isWrapped)
        #expect(terminal.screen[1].columnCount(at: 0) == 2)
        #expect(lines(terminal)[1].hasSuffix("b    "))
    }

    @Test func keepsTheWidthOfATabThatIsWiderThanTheColumns() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.receive("\u{1B}[3g\u{1B}[15G\u{1B}H\ra\tb")
        terminal.resize(columns: 5, rows: 3)
        terminal.resize(columns: 20, rows: 3)
        #expect(lines(terminal).first == "a             b     ")
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

    @Test func keepsTheTabStopsOnAResize() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}[3g\u{1B}[6G\u{1B}H\r")
        terminal.resize(columns: 4, rows: 1)
        terminal.resize(columns: 20, rows: 1)
        terminal.receive("\tx\ty")
        #expect(lines(terminal) == ["     x             y"])
    }

    @Test func usesTheDefaultTabStopsBeyondTheColumnsAfterAReset() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}[3g\u{1B}c")
        terminal.resize(columns: 20, rows: 1)
        terminal.receive("\t\tx")
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

    @Test(arguments: [("A", 3, 0), ("A", 5, 0), ("B", 2, 5), ("B", 0, 5), ("F", 3, 0), ("E", 2, 5)])
    func ignoresTheMarginsWithoutOriginMode(final: String, row: Int, stop: Int) {
        var terminal = Terminal(columns: 10, rows: 6)
        terminal.receive("\u{1B}[2;5r\u{1B}[\(row + 1);3H\u{1B}[10\(final)")
        #expect(terminal.cursor.row == stop)
    }

    @Test(arguments: [("A", 1), ("B", 4), ("F", 1), ("E", 4)])
    func stopsTheCursorAtTheMarginsInOriginMode(final: String, stop: Int) {
        var terminal = Terminal(columns: 10, rows: 6)
        terminal.receive("\u{1B}[2;5r\u{1B}[?6h\u{1B}[2;3H\u{1B}[10\(final)")
        #expect(terminal.cursor.row == stop)
    }

    @Test func countsRowsFromTheTopMarginInOriginMode() {
        var terminal = Terminal(columns: 10, rows: 6)
        #expect(terminal.receive("\u{1B}[2;5r\u{1B}[?6h\u{1B}[2;3H\u{1B}[6n") == "\u{1B}[2;3R")
        #expect(terminal.cursor == Terminal.Position(row: 2, column: 2))
        terminal.receive("\u{1B}[99d")
        #expect(terminal.cursor.row == 4)
    }

    @Test func keepsTheCursorWhenOriginModeEnds() {
        var terminal = Terminal(columns: 10, rows: 6)
        terminal.receive("\u{1B}[2;5r\u{1B}[?6h\u{1B}[2;3H\u{1B}[?6l")
        #expect(terminal.cursor == Terminal.Position(row: 2, column: 2))
    }

    @Test func restoresTheRowFromTheNewTopMarginInOriginMode() {
        var terminal = Terminal(columns: 10, rows: 8)
        terminal.receive("\u{1B}[5;8r\u{1B}[?6h\u{1B}[2;1H\u{1B}7\u{1B}[?6l\u{1B}[1;3r\u{1B}8")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test func savesOriginModeWithTheCursor() {
        var terminal = Terminal(columns: 10, rows: 6)
        terminal.receive("\u{1B}[2;5r\u{1B}[?6h\u{1B}7\u{1B}[?6l\u{1B}8\u{1B}[H")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test(arguments: ["a", "e"])
    func ignoresRelativePositionSequences(final: String) {
        var terminal = Terminal(columns: 10, rows: 10)
        terminal.receive("\u{1B}[2\(final)")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
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
        ("\u{1B}[5`", Terminal.Position(row: 1, column: 4)),
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
        ("\u{1B}[?1K", "abcd"),
    ])
    func erasesInLine(sequence: String, line: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\r\nefgh\u{1B}[1;3H\(sequence)")
        #expect(lines(terminal) == [line, "efgh"])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test(arguments: ["\u{1B}[K", "\u{1B}[J", "\u{1B}[P", "\u{1B}[X", "\u{1B}[@"])
    func keepsThePendingWrapOnErase(erase: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\(erase)e")
        #expect(lines(terminal) == ["abc ", "e   "])
    }

    @Test(arguments: ["\t", "\u{1B}[I", "\u{1B}[C", "\u{1B}[G"])
    func cancelsThePendingWrapOnAMove(move: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\(move)")
        let cursor = terminal.cursor
        terminal.receive("e")
        #expect(terminal.screen[1][0] == Terminal.Cell())
        #expect(terminal.cursor.row == cursor.row)
    }

    @Test func keepsThePendingWrapOnAVerticalPosition() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("abcd\u{1B}[2dx")
        #expect(lines(terminal) == ["abcd", "    ", "x   "])
    }

    @Test func keepsThePendingWrapOnAFullReset() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}cx")
        #expect(lines(terminal) == ["    ", "x   "])
    }

    @Test(arguments: [(1, 3), (2, 2), (3, 1), (4, 3), (5, 3), (6, 2), (8, 3), (9, 3)])
    func movesBackFromThePendingWrap(count: Int, column: Int) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}[\(count)D")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: column))
    }

    @Test func movesUpOverWrappedLinesFromThePendingWrap() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("abcdefghijkl\u{1B}[8D")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
    }

    @Test(arguments: ["\u{8}", "\u{1B}[D"])
    func movesBackOverAWrappedLine(back: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcde\r\(back)")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
    }

    @Test(arguments: ["\u{8}", "\u{1B}[D"])
    func staysAtTheStartOfAHardLine(back: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\r\ne\r\(back)")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test func movesBackOverALineInTheScrollback() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("abcde\r\u{8}")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
    }

    @Test func repeatsTheDroppedCharacterWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?7labcde\u{1B}[b")
        #expect(lines(terminal) == ["abce"])
    }

    @Test func dropsACombiningMarkAfterADroppedWideCharacter() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?7labc中\u{301}")
        #expect(lines(terminal) == ["abc "])
    }

    @Test(arguments: ["\u{261D}\u{1F3FD}", "\u{1F1FA}\u{1F1F8}"])
    func acceptsAnEmojiPairAtTheEndWithoutAutowrap(pair: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[?7labc\(pair)")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 3))
    }

    @Test func allowsTextAfterAResizeWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?7labcd")
        terminal.resize(columns: 8, rows: 1)
        terminal.receive("e")
        #expect(lines(terminal) == ["abce    "])
    }

    @Test func dropsTheRestOfTheTextWithoutAutowrap() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?7labcdef")
        #expect(lines(terminal) == ["abcd"])
        terminal.receive("\u{1B}[mg")
        #expect(lines(terminal) == ["abcg"])
    }

    @Test(arguments: [
        ("\u{1B}[J", ["abcd", "e   ", "    "]),
        ("\u{1B}[0J", ["abcd", "e   ", "    "]),
        ("\u{1B}[1J", ["    ", "  gh", "ijkl"]),
        ("\u{1B}[2J", ["    ", "    ", "    "]),
        ("\u{1B}[?J", ["abcd", "efgh", "ijkl"]),
    ])
    func erasesInDisplay(sequence: String, screen: [String]) {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("abcdefghijkl\u{1B}[2;2H\(sequence)")
        #expect(lines(terminal) == screen)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func erasesTheDisplayWithTheBackgroundColor() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("abc\u{1B}[44m\u{1B}[2Jx")
        #expect(lines(terminal) == ["  ", " x"])
        #expect(terminal.screen.flatMap { $0.map(\.style.background) } == Array(repeating: .indexed(4), count: 4))
        #expect(terminal.screen.map(\.isWrapped) == [false, false])
    }

    @Test(arguments: [
        ("\u{1B}[J", ["ab", "c ", "  "], [false, false, false, true, true, true], [true, false, false]),
        ("\u{1B}[1J", ["  ", "  ", "ef"], [true, true, true, true, false, false], [false, false, false]),
    ])
    func erasesRowsWithTheBackgroundColor(sequence: String, screen: [String], erased: [Bool], wrapped: [Bool]) {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("abcdef\u{1B}[2;2H\u{1B}[44m\(sequence)")
        #expect(lines(terminal) == screen)
        #expect(terminal.screen.flatMap { $0.map { $0.style.background == .indexed(4) } } == erased)
        #expect(terminal.screen.map(\.isWrapped) == wrapped)
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

    @Test func ignoresTheTitleStack() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}]2;A\u{7}\u{1B}[22t\u{1B}]2;B\u{7}\u{1B}[23tx") == "")
        #expect(terminal.title == "B")
        #expect(terminal.receive("\u{1B}[22;0t\u{1B}]2;C\u{7}\u{1B}[23;0t") == "")
        #expect(terminal.title == "C")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["x", " ", " ", " "])
    }

    @Test func ignoresOtherWindowOperations() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}]2;vim\u{7}\u{1B}[18t\u{1B}[24t")
        #expect(terminal.title == "vim")
    }

    @Test(arguments: ["\u{1B}]8;;https://example.com\u{7}", "\u{1B}]8;;https://example.com\u{1B}\\", "\u{1B}]8;u\u{7}"])
    func printsTheTextOfAHyperlinkWithNoLink(sequence: String) {
        var terminal = Terminal(columns: 10, rows: 2)
        var plain = terminal
        plain.receive("LINK label")
        #expect(terminal.receive(sequence + "LINK\u{1B}]8;;\u{7} label") == "")
        #expect(terminal.screen == plain.screen)
    }

    @Test func growsTheScreen() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\r\ncd")
        terminal.resize(columns: 3, rows: 3)
        #expect(lines(terminal) == ["ab ", "cd ", "   "])
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func keepsThePendingWrapInAResize() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("abc")
        terminal.resize(columns: 5, rows: 2)
        terminal.receive("d")
        #expect(lines(terminal) == ["abc  ", "d    "])
        #expect(terminal.screen[0].isWrapped)
    }

    @Test func movesACursorPastTheTextToTheNextRow() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("ab\r\ncd\u{1B}[1;5H")
        terminal.resize(columns: 8, rows: 3)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test func movesACursorAboveTheScreenToTheLastRow() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("a\r\nb\r\ncd\u{1B}[1;2H")
        terminal.resize(columns: 4, rows: 1)
        #expect(lines(terminal) == ["cd  "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test func movesTheCursorToTheHeadOfAWideCharacter() {
        var terminal = Terminal(columns: 5, rows: 2)
        terminal.receive("中\u{1B}[1;2H")
        terminal.resize(columns: 5, rows: 1)
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
    }

    @Test func movesTheCursorToTheHeadOfATab() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("a\tb\u{1B}[1;4H")
        terminal.resize(columns: 9, rows: 2)
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test func removesOnlyTheRowsWithTextAtTheTop() {
        var terminal = Terminal(columns: 2, rows: 4)
        terminal.receive("a\r\nb\r\nc\u{1B}[H")
        terminal.resize(columns: 2, rows: 2)
        #expect(scrollback(terminal) == ["a"])
    }

    @Test func returnsTheScrollbackWhenTheRowsGrow() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("a\r\nb\r\nc\r\nd")
        terminal.resize(columns: 2, rows: 3)
        #expect(lines(terminal) == ["b ", "c ", "d "])
        #expect(scrollback(terminal) == ["a"])
    }

    @Test func movesEachSavedCursorByTheRowChange() {
        var terminal = Terminal(columns: 4, rows: 4)
        terminal.receive("\u{1B}[2;2H\u{1B}7")
        terminal.resize(columns: 4, rows: 6)
        terminal.receive("\u{1B}8")
        #expect(terminal.cursor == Terminal.Position(row: 3, column: 1))
    }

    @Test func keepsTheScrollRegionOnAResize() {
        var terminal = Terminal(columns: 2, rows: 4)
        terminal.receive("\u{1B}[2;3r")
        terminal.resize(columns: 2, rows: 6)
        terminal.receive("\u{1B}[3;1Ha\r\nb")
        #expect(lines(terminal) == ["  ", "a ", "b ", "  ", "  ", "  "])
    }

    @Test func doesNothingWhenTheScrollRegionIsBelowTheScreen() {
        var terminal = Terminal(columns: 2, rows: 6)
        terminal.receive("\u{1B}[5;6r\u{1B}[Ha\r\nb")
        terminal.resize(columns: 2, rows: 2)
        let screen = terminal.screen
        terminal.receive("\u{1B}[S\u{1B}[T")
        #expect(terminal.screen == screen)
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func rewrapsEveryLineWhenOnlyTheRowsChange() {
        var terminal = Terminal(columns: 3, rows: 4)
        terminal.receive("abc")
        terminal.resize(columns: 5, rows: 4)
        terminal.receive("d\u{1B}[4;1H")
        terminal.resize(columns: 5, rows: 3)
        terminal.receive("\u{1B}[2;1He")
        #expect(lines(terminal) == ["abcd ", "e    ", "     "])
    }

    @Test func unwrapsTheRowWhenItDeletesCharacters() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("abcde\u{1B}[1;1H\u{1B}[P")
        #expect(!terminal.screen[0].isWrapped)
    }

    @Test func extendsTheEraseColorToTheNewWidth() {
        var terminal = Terminal(columns: 3, rows: 2)
        terminal.receive("a\u{1B}[41m\u{1B}[K\u{1B}[m\r\nb")
        terminal.resize(columns: 5, rows: 2)
        #expect(terminal.screen[0].map(\.style.background) == [.default] + Array(repeating: .indexed(1), count: 4))
        #expect(terminal.screen[1][4].style.background == .default)
    }

    @Test func blanksTheSecondHalfPastTheColumnsWhenItWritesTheHead() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}[?1049h\u{1B}[1;9H中")
        terminal.resize(columns: 9, rows: 1)
        terminal.receive("\u{1B}[1;9Hx")
        terminal.resize(columns: 10, rows: 1)
        terminal.receive("\u{1B}[1;10Hy")
        #expect(lines(terminal) == ["        xy"])
    }

    @Test func reportsAnOriginRowAboveTheScrollRegionAsUnsigned() {
        var terminal = Terminal(columns: 2, rows: 6)
        terminal.receive("\u{1B}[5;6r\u{1B}[?6h")
        terminal.resize(columns: 2, rows: 3)
        #expect(terminal.receive(Array("\u{1B}[6n".utf8)) == Array("\u{1B}[18446744073709551615;2R".utf8))
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
        #expect(scrollback(terminal).contains { $0.hasPrefix("AAAAABBB") })
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
        terminal.receive("abcde")
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
        let (lines, cursor) = Terminal.reflow(
            terminal.screen,
            columns: 1,
            cursor: Terminal.Position(row: 0, column: 9)
        )
        #expect(lines.count == 9)
        #expect(cursor == Terminal.Position(row: 8, column: 0))
    }

    @Test func reflowsTheCursorLine() {
        var terminal = Terminal(columns: 10, rows: 4)
        terminal.receive("$ echo 0123456789")
        terminal.resize(columns: 5, rows: 4)
        #expect(lines(terminal) == ["$ ech", "o 012", "34567", "89   "])
        #expect(terminal.screen.map(\.isWrapped) == [true, true, true, false])
        #expect(terminal.cursor == Terminal.Position(row: 3, column: 2))
    }

    @Test(arguments: [(3, "\u{1B}[?47h")])
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
        terminal.receive("aaaaaaaa\r\nbbbbbbbb\r\n$ \u{1B}[?47h")
        terminal.resize(columns: 4, rows: 3)
        terminal.receive("\u{1B}[?47l")
        #expect(scrollback(terminal) == ["aaaa", "aaaa"])
        #expect(lines(terminal) == ["bbbb", "bbbb", "$   "])
    }

    @Test func keepsTheCursorLineOfTheNormalScreenWhenTheRowsChange() {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[?47h")
        terminal.resize(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?47l")
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
        #expect(scrollback(terminal) == Array(repeating: "JJJJJ", count: 7))
        #expect(lines(terminal) == ["JJJJJ", "JJJJJ", "$    "])
    }

    @Test func keepsTheSavedCursorOnItsCharacter() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("0123456789abc\u{1B}7\r\n")
        terminal.resize(columns: 5, rows: 3)
        terminal.receive("\u{1B}8X")
        #expect(lines(terminal) == ["56789", "abcX ", "     "])
    }

    @Test func keepsThePendingWrapOnTheAlternateScreen() {
        var terminal = Terminal(columns: 5, rows: 3)
        terminal.receive("\u{1B}[?1049habcde")
        terminal.resize(columns: 8, rows: 3)
        terminal.receive("f")
        #expect(lines(terminal).prefix(2) == ["abcde   ", "f       "])
    }

    @Test func addsTheNewRowsOfTheAlternateScreenAtTheTop() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("\u{1B}[?1049ha\r\nb\u{1B}[H")
        terminal.resize(columns: 2, rows: 3)
        #expect(lines(terminal) == ["  ", "a ", "b "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
    }

    @Test func removesTheTopRowsOfTheAlternateScreen() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("\u{1B}[?1049ha\r\nb\r\nc\u{1B}[H")
        terminal.resize(columns: 2, rows: 2)
        #expect(lines(terminal) == ["b ", "c "])
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
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

    @Test(arguments: [("\u{1B}[s", "\u{1B}[u"), ("\u{1B}[?1048h", "\u{1B}[?1048l")])
    func ignoresTheOtherCursorSaves(save: String, restore: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\(save)cd\r\n\(restore)x")
        #expect(lines(terminal) == ["abcd", "x   "])
    }

    @Test func keepsTheHomeCursorFromAMark() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\u{1B}[?1049h\u{1F3FD}")
        #expect(terminal.cursor.row == 1)
    }

    @Test func usesTheDefaultBackgroundOnTheFirstAlternateScreen() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[44m\u{1B}[?47h")
        #expect(terminal.screen[0][0] == Terminal.Cell())
    }

    @Test func usesTheBackgroundWhen1049ClearsTheScreen() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[44m\u{1B}[?1049h")
        #expect(terminal.screen[0][0].style.background == .indexed(4))
    }

    @Test func movesToTheSecondColumnFromAPendingWrapAtTheHome() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}[?1049h\u{1B}[3D")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 1))
    }

    @Test func repeatsWithoutTheWrapFromAPendingWrapAtTheHome() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}[?1049h\u{1B}[2b")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
    }

    @Test func ignoresMode1047() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?1047hx\u{1B}[?1047lc")
        #expect(lines(terminal) == ["abxc", "    "])
        #expect(!terminal.isAlternateScreenActive)
    }

    @Test func restoresTheSavedStyle() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[1;31m\u{1B}7\u{1B}[m\u{1B}8a")
        #expect(terminal.screen[0][0].style == Terminal.Style(foreground: .indexed(1), isBold: true))
    }

    @Test func clearsThePendingWrapWhenItRestoresTheCursor() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\u{1B}7\r\u{1B}8c")
        #expect(lines(terminal) == ["ac", "  "])
    }

    @Test(arguments: [(8, ["abcX    ", "        ", "        "]), (2, ["aXcd", "    ", "    "])])
    func cancelsTheSavedPendingWrapOnTheAlternateScreen(columns: Int, lines expected: [String]) {
        var terminal = Terminal(columns: 4, rows: 3)
        terminal.receive("\u{1B}[?1049habcd\u{1B}7")
        terminal.resize(columns: columns, rows: 3)
        terminal.receive("\u{1B}8X")
        #expect(lines(terminal) == expected)
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
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
    }

    @Test func restoresTheNormalScreenAndCursor() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?1049h\u{1B}[2;3Hxy\u{1B}[?1049lc")
        #expect(lines(terminal) == ["abc ", "    "])
    }

    @Test func restoresThePositionWithMode47() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?47hx\u{1B}[?47lc")
        #expect(lines(terminal) == ["abc ", "    "])
    }

    @Test func homesTheCursorWithMode47() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[?47h")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 0))
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

    @Test(arguments: [47, 1049])
    func clearsTheAlternateScreenOnEach1049(mode: Int) {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("\u{1B}[?\(mode)hxy\r\nz\u{1B}[A\u{1B}[44m\u{1B}[?1049h")
        #expect(lines(terminal) == ["  ", "  "])
        #expect(terminal.screen.flatMap { $0.map(\.style.background) } == Array(repeating: .indexed(4), count: 4))
    }

    @Test func keepsTheAlternateScreenOnASecondSwitch() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1049hxz\u{1B}[?47hy")
        #expect(lines(terminal) == ["yz  "])
    }

    @Test func keepsTheAlternateScreenBetweenSwitches() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?47hxz\u{1B}[?47l\u{1B}[?47hy")
        #expect(lines(terminal) == ["yz  "])
    }

    @Test func clearsTheAlternateScreenOnEachSwitchTo1049() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1049hxz\u{1B}[?1049hy")
        #expect(lines(terminal) == ["y   "])
    }

    @Test func savesTheCursorOnASecond1049() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?1049h\u{1B}[3G\u{1B}[?1049h\u{1B}[H\u{1B}8x")
        #expect(lines(terminal) == ["  x "])
    }

    @Test func keepsThePendingWrapOn1049() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("abcd\u{1B}[?1049hx")
        #expect(lines(terminal) == ["x   "])
    }

    @Test(arguments: [47, 1049])
    func restoresTheNormalCursorAfterASecondSwitch(mode: Int) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("ab\u{1B}7\u{1B}[?\(mode)hx\u{1B}[?1049h\u{1B}[?1049lc")
        #expect(lines(terminal) == ["abc "])
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

    @Test func movesToTheLastLineFromTheFirstLineAboveTheScrollRegion() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\u{1B}[2;3r\u{1B}[1H\u{1B}Mx")
        #expect(lines(terminal) == ["a", " ", "x"])
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

    @Test(arguments: ["L", "M"])
    func keepsTheColumnWhenItChangesLines(final: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("ab\u{1B}[\(final)")
        #expect(terminal.cursor == Terminal.Position(row: 0, column: 2))
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
        #expect(terminal.receive("\u{1B}[1c\u{1B}[0;0c") == "")
        #expect(terminal.receive("\u{1B}[>c") == "\u{1B}[>1;95;0c")
        #expect(terminal.receive("\u{1B}[>0c") == "\u{1B}[>1;95;0c")
        #expect(terminal.receive("\u{1B}[>1c\u{1B}[>0;0c") == "")
    }

    @Test func countsTheBells() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a\u{7}b\u{7}\u{7}")
        #expect(terminal.bellCount == 3)
        #expect(terminal.screen[0].prefix(2).map(terminal.character(of:)) == ["a", "b"])
    }

    @Test func setsATitleThatStartsWithACombiningMark() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}]2;\u{301}x\u{7}")
        #expect(terminal.title == "\u{301}x")
    }

    @Test func ignoresABellAsTheEndOfACommand() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}]0;title\u{7}")
        #expect(terminal.bellCount == 0)
    }

    @Test(arguments: ["\u{1B}P1;2\u{7}x\u{1B}\\", "\u{1B}_\u{7}\u{1B}\\"])
    func ringsTheBellInAStringOfOtherControls(string: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive(string)
        #expect(terminal.bellCount == 1)
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

    @Test(arguments: ["\u{1B}[7 q", "\u{1B}[2q", "\u{1B}[2!q", "\u{1B}[2 p"])
    func ignoresOtherCursorShapeSequences(sequence: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[5 q" + sequence + "x")
        #expect(terminal.cursorShape == .bar)
        #expect(terminal.character(of: terminal.screen[0][0]) == "x")
    }

    @Test func printsTheFinalOfAMarkedCursorShapeSequence() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[5 q\u{1B}[?2 qx")
        #expect(terminal.cursorShape == .bar)
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["q", "x", " ", " "])
    }

    @Test(arguments: ["\u{1B}[m", "\r", "\n", "\u{8}", "\t", "\u{1B}[3;3H", "\u{1B}]2;t\u{7}"])
    func repeatsTheCharacterAfterAControlFunction(control: String) {
        var terminal = Terminal(columns: 10, rows: 4)
        terminal.receive("a\(control)\u{1B}[2b")
        #expect(terminal.screen.flatMap { $0 }.count { terminal.character(of: $0) == "a" } >= 2)
    }

    @Test(arguments: ["é", "中", "\u{1F600}", "\u{A0}"])
    func repeatsNothingAfterANonASCIICharacter(character: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("a\(character)")
        let cursor = terminal.cursor
        terminal.receive("\u{1B}[2b")
        #expect(terminal.cursor == cursor)
    }

    @Test func repeatsSpacesBeforeACharacter() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}[3bx")
        #expect(lines(terminal) == ["   x      "])
    }

    @Test(arguments: ["\u{1B}c", "\u{1B}[!p"])
    func repeatsSpacesAfterAReset(reset: String) {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("a\(reset)\u{1B}[H\u{1B}[2bx")
        #expect(lines(terminal) == ["  x       "])
    }

    @Test func repeatsSpacesAfterALineDrawingCharacter() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}(0q\u{1B}(B\u{1B}[2bx")
        #expect(lines(terminal) == ["─  x      "])
    }

    @Test func repeatsTheCharacterAsItWasPrinted() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("q\u{1B}(0\u{1B}[2b\u{1B}(B")
        #expect(lines(terminal) == ["qqq       "])
    }

    @Test func countsTheWrapAsARepeat() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("ab\u{1B}[2bx")
        #expect(lines(terminal) == ["ab", "bx"])
    }

    @Test func limitsTheRepeats() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("a\u{1B}[2147483647b")
        #expect(terminal.cursor.column == 1)
    }

    @Test func repeatsWithoutAutowrapUntilTheLastColumn() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?7la\u{1B}[9bx")
        #expect(lines(terminal) == ["aaax"])
    }

    @Test func acceptsTheLargestParameterForEachFinal() {
        for final in (0x40 ... 0x7E).compactMap(UnicodeScalar.init) {
            var terminal = Terminal(columns: 4, rows: 2)
            terminal.receive("ab\u{1B}[2147483647;2147483647\(final)")
            #expect(terminal.rows == 2)
        }
    }

    @Test func joinsTheDigitsAroundAColonInAControlSequence() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[0:2H")
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 0))
    }

    @Test func ignoresAColonInACursorShapeSequence() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive("\u{1B}[5 q\u{1B}[2:1 q")
        #expect(terminal.cursorShape == .bar)
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

    @Test func setsTheApplicationKeypadMode() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(!terminal.usesApplicationKeypad)
        terminal.receive("\u{1B}=")
        #expect(terminal.usesApplicationKeypad)
        terminal.receive("\u{1B}[?1049h\u{1B}[?1049l")
        #expect(terminal.usesApplicationKeypad)
        terminal.receive("\u{1B}>")
        #expect(!terminal.usesApplicationKeypad)
        terminal.receive("\u{1B}=\u{1B}[!p")
        #expect(!terminal.usesApplicationKeypad)
        terminal.receive("\u{1B}=\u{1B}c")
        #expect(!terminal.usesApplicationKeypad)
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

    @Test func keepsTheBlankLinesThatScrollOffTheScreen() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("a\u{1B}[9S\u{1B}[44m\u{1B}[2H\u{1B}[K\u{1B}[9S\u{1B}[9S")
        #expect(scrollback(terminal) == ["a", "", "", "  ", "  ", "  "])
    }

    @Test(arguments: ["\u{20}", "\u{1B}[X", "\u{1B}[1K", "\u{1B}[1J", "\u{1B}[@"])
    func writesSpaces(sequence: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("a\u{1B}[3Gb\u{1B}[G" + sequence)
        #expect(terminal.screen[0].first.map(terminal.character(of:)) == " ")
        #expect(terminal.screen[0].first?.isWritten == true)
    }

    @Test(arguments: ["\u{1B}[K", "\u{1B}[2K", "\u{1B}[J", "\u{1B}[2J", "\u{1B}[P"])
    func clearsWithoutWritingSpaces(sequence: String) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("abcd\u{1B}[H" + sequence)
        #expect(terminal.screen[0].last?.isWritten == false)
    }

    @Test func keepsWrittenSpacesInTheScrollback() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a \u{1B}[K\r\nb  \r\n")
        #expect(terminal.scrollback.map(\.count) == [2, 3])
    }

    @Test func keepsTheWrapOfEachLineThatScrollsOffTheScreen() {
        var terminal = Terminal(columns: 2, rows: 2)
        terminal.receive("a a \u{1B}[2S")
        #expect(scrollback(terminal) == ["a ", "a "])
        #expect(terminal.scrollback.map(\.isWrapped) == [true, false])
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

    @Test func keepsALineDeletedFromTheTop() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("a\u{1B}[H\u{1B}[M")
        #expect(scrollback(terminal) == ["a"])
    }

    @Test func keepsNoOtherDeletedLines() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("a\r\nb\u{1B}[M")
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func keepsNoLineDeletedOnTheAlternateScreen() {
        var terminal = Terminal(columns: 1, rows: 2)
        terminal.receive("\u{1B}[?1049ha\u{1B}[H\u{1B}[M")
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func keepsTheScreenInTheScrollbackOnEraseInDisplay() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a\r\nb\u{1B}[2J\u{1B}[2J")
        #expect(terminal.scrollback.count == 6)
        #expect(terminal.cursor == Terminal.Position(row: 1, column: 1))
    }

    @Test func keepsTheRowsWhenItErasesABlankScreen() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("\u{1B}[2J")
        #expect(terminal.scrollback.count == 3)
    }

    @Test func keepsNothingOnEraseInDisplayOnTheAlternateScreen() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("\u{1B}[?1049ha\u{1B}[2J")
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func clearsTheNormalScreenOnEraseOfTheScrollbackOnTheAlternateScreen() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("a\u{1B}[?1049h\u{1B}[3J\u{1B}[?1049l")
        #expect(lines(terminal) == ["  "])
    }

    @Test func keepsTheLinesThatAResizeRemoves() {
        var terminal = Terminal(columns: 2, rows: 3)
        terminal.receive("a\r\nb\r\nc")
        terminal.resize(columns: 2, rows: 1)
        #expect(scrollback(terminal) == ["a", "b"])
    }

    @Test func keepsTheNormalLinesThatAResizeRemovesOnTheAlternateScreen() {
        var terminal = Terminal(columns: 1, rows: 3)
        terminal.receive("a\r\nb\r\nc\u{1B}[?1049h")
        terminal.resize(columns: 1, rows: 1)
        #expect(scrollback(terminal) == ["a", "b"])
    }

    @Test func survivesRandomOutputAndResizes() {
        let fragments = [
            "abc", "\r\n", "\t", "中", "e\u{301}", "\u{8}", "\u{1B}[H", "\u{1B}[5;9H", "\u{1B}[99;99H", "\u{1B}[2J",
            "\u{1B}[3J",
            "\u{1B}[J", "\u{1B}[1J", "\u{1B}[K", "\u{1B}[1K", "\u{1B}[2K", "\u{1B}[2L", "\u{1B}[2M", "\u{1B}[2S",
            "\u{1B}[2T",
            "\u{1B}[2@", "\u{1B}[2P", "\u{1B}[5X", "\u{1B}M", "\u{1B}D", "\u{1B}7", "\u{1B}8", "\u{1B}#8",
            "\u{1B}[3;8r", "\u{1B}[8;20r",
            "\u{1B}[r", "\u{1B}[?6h", "\u{1B}[?6l", "\u{1B}[?7l", "\u{1B}[?7h", "\u{1B}[?47h", "\u{1B}[?47l",
            "\u{1B}[?1049h",
            "\u{1B}[?1049l", "\u{1B}[3g", "\u{1B}H", "\u{1B}[!p", "\u{1B}c", "\u{1B}[41m", "\u{1B}[m", "\u{1B}[3b",
            "\u{1B}[6n",
            String(repeating: "K", count: 45),
        ]
        var state: UInt64 = 0x1234_5678
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        var terminal = Terminal(columns: 20, rows: 8)
        for _ in 0 ..< 20_000 {
            if next(8) == 0 {
                terminal.resize(columns: next(50) + 1, rows: next(25) + 1)
            } else {
                terminal.receive(fragments[next(fragments.count)])
            }
            #expect(terminal.screen.count == terminal.rows)
            #expect(terminal.screen.allSatisfy { $0.count >= terminal.columns })
            #expect((0 ..< terminal.rows).contains(terminal.cursor.row))
            #expect((0 ..< terminal.columns).contains(terminal.cursor.column))
        }
    }

    @Test func laysOutTheSavedLinesLikeAFullReflow() {
        let fragments = [
            "abc", "\r\n", "\n", "\t", "x\ty", "中", "中文字", "e\u{301}", "\u{1B}[41m", "\u{1B}[m", "\u{1B}[5X",
            "\u{1B}[K", "\u{1B}[1K", "\u{1B}[2J", "\u{1B}M", "\u{1B}[A", "\u{1B}[3D", "\u{1B}[2P",
            "KKKKKK", String(repeating: "K", count: 37), String(repeating: "中", count: 23),
        ]
        var state: UInt64 = 0x9ABC_DEF0
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        var terminal = Terminal(columns: 12, rows: 3)
        for step in 0 ..< 6_000 {
            if next(10) == 0 {
                terminal.resize(columns: [6, 12, 18, 24][next(4)] + next(3) - 1, rows: next(6) + 1)
            } else {
                terminal.receive(fragments[next(fragments.count)])
            }
            if terminal.scrollback.count > 300 {
                terminal.receive("\u{1B}[3J")
            }
            guard step % 7 == 0 else {
                continue
            }
            let scrollback = terminal.scrollback
            var paragraphs: [[Terminal.Line]] = []
            for line in scrollback.lines {
                if paragraphs.isEmpty || paragraphs[paragraphs.count - 1].last?.isWrapped == false {
                    paragraphs.append([line])
                } else {
                    paragraphs[paragraphs.count - 1].append(line)
                }
            }
            let expected = paragraphs.indices.flatMap { index in
                index < scrollback.relaidCount
                    ? Terminal.laidOut(paragraphs[index][...], columns: terminal.columns) : paragraphs[index]
            }
            #expect(Array(scrollback) == expected)
            #expect(scrollback.indices.map { scrollback[$0] } == expected)
        }
    }

    @Test func resizesLikeARewrapOfEverySavedLine() {
        let fragments = [
            "abc", "\r\n", "\n", "\t", "x\ty", "中文字", "\u{1B}[41m", "\u{1B}[m", "\u{1B}[5X", "\u{1B}[K",
            "\u{1B}[2J", "\u{1B}M", "\u{1B}[A", "\u{1B}[H", "\u{1B}[2P", "\u{1B}7", "\u{1B}8", "\u{1B}[2;4r",
            "\u{1B}[r", "\u{1B}[?1049h", "\u{1B}[?1049l", "\u{1B}[?47h", "\u{1B}[?47l", "\u{1B}[?7l", "\u{1B}[?7h",
            String(repeating: "K", count: 37), String(repeating: "中", count: 23),
        ]
        var state: UInt64 = 0x5555_AAAA
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        var terminal = Terminal(columns: 12, rows: 4)
        for _ in 0 ..< 6_000 {
            guard next(8) == 0 else {
                terminal.receive(fragments[next(fragments.count)])
                continue
            }
            let columns = [1, 5, 12, 20][next(4)] + next(3)
            let rows = next(7) + 1
            var full = terminal
            terminal.resize(columns: columns, rows: rows)
            full.resize(columns: columns, rows: rows, restoredRows: .max)
            #expect(terminal.screen == full.screen)
            #expect(terminal.cursor == full.cursor)
            #expect(terminal.normalScreenLines == full.normalScreenLines)
            #expect(Array(terminal.scrollback) == Array(full.scrollback))
            if terminal.scrollback.count > 300 {
                terminal.receive("\u{1B}[3J")
            }
        }
    }

    @Test func laysOutALongSavedLineWithManyWidthRuns() {
        var terminal = Terminal(columns: 80, rows: 3)
        terminal.receive(String(repeating: "中\tx", count: 600) + String(repeating: "\r\nx", count: 20))
        for columns in [97, 31, 64] {
            terminal.resize(columns: columns, rows: 3)
            let scrollback = terminal.scrollback
            let end = scrollback.lines.firstIndex { !$0.isWrapped }.map { $0 + 1 } ?? 0
            let expected = Terminal.laidOut(scrollback.lines[..<end], columns: columns)
            #expect(expected.count > 40)
            #expect(Array(scrollback.prefix(expected.count)) == expected)
            #expect(expected.indices.reversed().map { scrollback[$0] } == expected.reversed())
        }
    }

    @Test func laysOutRandomSavedCellsLikeAFullReflow() {
        let red = Terminal.Style(background: .indexed(1))
        var state: UInt64 = 0x0F1E_2D3C
        func next(_ limit: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(limit))
        }
        func cells() -> [Terminal.Cell] {
            switch next(8) {
            case 0: [Terminal.Cell(scalar: "中", width: 2), Terminal.Cell(width: 0)]
            case 5: [Terminal.Cell(width: 0)]
            case 1: [.tab(style: Terminal.Style())] + Array(repeating: .tabGap(style: Terminal.Style()), count: next(9))
            case 2: [.tabGap(style: Terminal.Style())]
            case 3: [.writtenSpace(), Terminal.Cell()]
            case 4: [Terminal.Cell(style: red)]
            default: [Terminal.Cell(scalar: "a")]
            }
        }
        for _ in 0 ..< 400 {
            var scrollback = Terminal.Scrollback(columns: 10)
            var paragraphs: [[Terminal.Line]] = []
            for _ in 0 ..< 6 {
                var rows: [Terminal.Line] = []
                for _ in 0 ..< next(4) + 1 {
                    rows.append(Terminal.Line((0 ..< next(8)).flatMap { _ in cells() }, isWrapped: true))
                }
                rows[rows.count - 1].isWrapped = false
                rows = rows.map(Terminal.trimmed)
                for row in rows {
                    scrollback.append(row)
                }
                paragraphs.append(rows)
            }
            for _ in 0 ..< 4 {
                let columns = [1, 2, 3, 5, 8, 13][next(6)]
                scrollback.relayOut(columns: columns)
                let expected = paragraphs.flatMap { Terminal.laidOut($0[...], columns: columns) }
                #expect(Array(scrollback) == expected)
                #expect(scrollback.indices.map { scrollback[$0] } == expected)
            }
        }
    }

    @Test func keepsTheEmptyRowOfASavedFullLineAtAnExactWidth() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\r\nabcd")
        terminal.resize(columns: 4, rows: 2)
        terminal.receive("\r\n\r\n1\r\n2\r\n3\r\n4\r\n5")
        terminal.resize(columns: 2, rows: 2)
        #expect(scrollback(terminal).prefix(4) == ["", "ab", "cd", ""])
        #expect(terminal.scrollback.map(\.isWrapped).prefix(4) == [false, true, true, false])
        terminal.resize(columns: 3, rows: 2)
        #expect(scrollback(terminal).prefix(3) == ["", "abc", "d"])
    }

    @Test func keepsEveryLineInTheScrollback() {
        var terminal = Terminal(columns: 5, rows: 1)
        terminal.receive((1 ... 12_000).map { "\($0)\r\n" }.joined())
        #expect(terminal.scrollback.count == 12_000)
        #expect(terminal.removedScrollbackCount == 0)
        #expect(scrollback(terminal).first == "1")
        #expect(scrollback(terminal).last == "12000")
    }
}

private func lines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { $0.map(terminal.character(of:)).joined().replacing("\t", with: " ") }
}

private func scrollback(_ terminal: Terminal) -> [String] {
    terminal.scrollback.map { $0.map(terminal.character(of:)).joined() }
}

struct WindowReportTests {
    @Test func reportsTheWindowFields() {
        var terminal = Terminal(columns: 40, rows: 12)
        terminal.windowReport = Terminal.WindowReport(isVisible: true, x: 12, y: 34, width: 56, height: 78)
        #expect(terminal.receive("\u{1B}[11t") == "\u{1B}[1t")
        #expect(terminal.receive("\u{1B}[13t") == "\u{1B}[3;12;34t")
        #expect(terminal.receive("\u{1B}[14t") == "\u{1B}[4;78;56t")
        #expect(terminal.receive("\u{1B}[18t") == "\u{1B}[8;12;40t")
    }

    @Test func keepsTheWindowReportAfterAReset() {
        var terminal = Terminal(columns: 40, rows: 12)
        terminal.windowReport = Terminal.WindowReport(isVisible: true, x: 12, y: 34, width: 56, height: 78)
        #expect(terminal.receive("\u{1B}c\u{1B}[13t") == "\u{1B}[3;12;34t")
    }
}
