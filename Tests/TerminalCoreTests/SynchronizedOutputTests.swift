import Testing

@testable import TerminalCore

struct SynchronizedOutputTests {
    @Test func showsTheScreenOfTheStartUntilTheEnd() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("a\u{1B}[?2026hb\r\nc")
        #expect(terminal.isSynchronizingOutput)
        #expect(lines(terminal.displayed) == ["a   ", "    "])
        #expect(terminal.displayed.cursor == Terminal.Position(row: 0, column: 1))
        #expect(lines(terminal) == ["ab  ", "c   "])

        terminal.receive("d\u{1B}[?2026l")
        #expect(!terminal.isSynchronizingOutput)
        #expect(lines(terminal.displayed) == ["ab  ", "cd  "])
        #expect(terminal.displayed.cursor == Terminal.Position(row: 1, column: 2))
    }

    @Test(arguments: [
        ("S", "\u{1B}[5;1Hg", ["a", "c", "d", "e", "g", "f"]),
        ("T", "\u{1B}[2;1Hg", ["a", "g", "b", "c", "d", "f"]),
    ])
    func drawsTheScrollFrameOfClaudeCode(command: String, text: String, expected: [String]) {
        var terminal = Terminal(columns: 1, rows: 6)
        terminal.receive("\u{1B}[?1049ha\r\nb\r\nc\r\nd\r\ne\r\nf")
        terminal.receive("\u{1B}[?2026h\u{1B}[2;5r\u{1B}[1\(command)\u{1B}[r\u{1B}[H\(text)")
        #expect(lines(terminal.displayed) == ["a", "b", "c", "d", "e", "f"])

        terminal.receive("\u{1B}[?2026l")
        #expect(lines(terminal.displayed) == expected)

        terminal.receive("\u{1B}[H\u{1B}[6;1H\n")
        #expect(lines(terminal).first == expected[1])
    }

    @Test func showsTheNewScrollbackAboveTheScreenOfTheStart() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("a\r\nb\u{1B}[?2026h\r\nc\r\nd")
        #expect(lines(terminal.displayed) == ["a   ", "b   "])
        #expect(terminal.displayed.scrollback.elementsEqual(terminal.scrollback))
        #expect(terminal.displayed.scrollback.count == 2)

        terminal.receive("\u{1B}[3J")
        #expect(terminal.displayed.scrollback.isEmpty)
        #expect(terminal.displayed.removedScrollbackCount == 2)
    }

    @Test func keepsTheFirstScreenWhenItStartsAgain() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a\u{1B}[?2026hb\u{1B}[?2026hc")
        #expect(lines(terminal.displayed) == ["a   "])
        #expect(terminal.synchronizedOutputCount == 1)

        terminal.receive("\u{1B}[?2026l\u{1B}[?2026ld\u{1B}[?2026h")
        #expect(lines(terminal.displayed) == ["abcd"])
        #expect(terminal.synchronizedOutputCount == 2)
    }

    @Test func endsWhenAskedOrResizedOrReset() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?2026ha")
        terminal.endSynchronizedOutput()
        #expect(lines(terminal.displayed) == ["a   "])

        terminal.receive("\u{1B}[?2026hb")
        terminal.resize(columns: 5, rows: 1)
        #expect(lines(terminal.displayed) == ["ab   "])

        terminal.receive("\u{1B}[?2026hc\u{1B}c")
        #expect(!terminal.isSynchronizingOutput)
        #expect(lines(terminal.displayed) == ["     "])
    }

    @Test func countsTheUpdatesAcrossAReset() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?2026h\u{1B}c\u{1B}[?2026h")
        #expect(terminal.synchronizedOutputCount == 2)
    }

    @Test func keepsTheModeAcrossTheAlternateScreen() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a\u{1B}[?2026h\u{1B}[?1049hb")
        #expect(lines(terminal.displayed) == ["a   "])
        #expect(!terminal.displayed.isAlternateScreenActive)

        terminal.receive("\u{1B}[?1049l")
        #expect(terminal.isSynchronizingOutput)
    }

    @Test func showsNewCharactersInTheScrollbackDuringAnUpdate() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("\u{1B}[?2026he\u{301}\r\nx")
        let displayed = terminal.displayed
        #expect(displayed.character(of: displayed.scrollback[0][0]) == "e\u{301}")
    }
}

private func lines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { $0.map(terminal.character(of:)).joined() }
}
