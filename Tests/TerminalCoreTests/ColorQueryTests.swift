import Testing

@testable import TerminalCore

struct ColorQueryTests {
    @Test(arguments: ["\u{7}", "\u{1B}\\"])
    func endsTheReplyWithBell(terminator: String) {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}]11;?\(terminator)") == "\u{1B}]11;rgb:ffff/fefe/0000\u{7}")
    }

    @Test func doesNotSwapTheColorsInReverseVideo() {
        var terminal = coloredTerminal()
        #expect(
            terminal.receive("\u{1B}[?5h\u{1B}]10;?;?\u{7}")
                == "\u{1B}]10;rgb:0001/abcd/1234\u{7}\u{1B}]11;rgb:ffff/fefe/0000\u{7}")
    }

    @Test func answersNothingWithoutColors() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.receive("\u{1B}]10;?\u{7}\u{1B}]4;1;?\u{7}") == "")
    }

    @Test func answersTheFixedColorsWithoutColors() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.receive("\u{1B}]13;?\u{7}") == "\u{1B}]13;rgb:0000/0000/0000\u{7}")
        #expect(terminal.receive("\u{1B}]4;16;?\u{7}") == "\u{1B}]4;16;rgb:0000/0000/0000\u{7}")
    }

    @Test func keepsTheColorsAfterAReset() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}c\u{1B}]11;?\u{7}") == "\u{1B}]11;rgb:ffff/fefe/0000\u{7}")
    }

    @Test func recordsTheChanges() {
        var terminal = coloredTerminal()
        terminal.receive("\u{1B}]10;#102030;#203040;#304050\u{7}\u{1B}]17;#405060\u{7}")
        terminal.receive("\u{1B}]4;2;#506070;256;#607080\u{7}")
        let changes = terminal.changedColors
        #expect(changes.foreground == Terminal.RGB(red: 0x1000, green: 0x2000, blue: 0x3000))
        #expect(changes.background == Terminal.RGB(red: 0x2000, green: 0x3000, blue: 0x4000))
        #expect(changes.cursor == Terminal.RGB(red: 0x3000, green: 0x4000, blue: 0x5000))
        #expect(changes.selection == Terminal.RGB(red: 0x4000, green: 0x5000, blue: 0x6000))
        #expect(changes.indexed == [2: Terminal.RGB(red: 0x5000, green: 0x6000, blue: 0x7000)])
        #expect(changes.bold == Terminal.RGB(red: 0x6000, green: 0x7000, blue: 0x8000))
    }

    @Test func clearsOnlyTheIndexedColorsOnAReset() {
        for reset in ["\u{1B}c", "\u{1B}[!p"] {
            var terminal = coloredTerminal()
            terminal.receive("\u{1B}]10;#102030\u{7}\u{1B}]4;2;#506070;256;#607080\u{7}" + reset)
            #expect(terminal.changedColors.indexed.isEmpty)
            #expect(terminal.changedColors.foreground != nil)
            #expect(terminal.changedColors.bold != nil)
        }
    }

    @Test func resetsEachDynamicColor() {
        var terminal = coloredTerminal()
        terminal.receive("\u{1B}]10;#111;#222;#333\u{7}\u{1B}]17;#444\u{7}")
        terminal.receive("\u{1B}]5;0;#555\u{7}\u{1B}]4;1;#666\u{7}")
        terminal.receive("\u{1B}]110\u{7}\u{1B}]111;\u{7}\u{1B}]112\u{7}\u{1B}]117\u{7}")
        terminal.receive("\u{1B}]105;0\u{7}\u{1B}]104\u{7}")
        #expect(terminal.changedColors.isEmpty)
    }
}

private func coloredTerminal() -> Terminal {
    var terminal = Terminal(columns: 1, rows: 1)
    terminal.defaultColors = Terminal.DefaultColors(
        foreground: Terminal.RGB(red: 0x0001, green: 0xABCD, blue: 0x1234),
        background: Terminal.RGB(red: 0xFFFF, green: 0xFEFE, blue: 0x0000),
        cursor: Terminal.RGB(red: 0, green: 0, blue: 0),
        selection: Terminal.RGB(red: 0, green: 0, blue: 0),
        bold: Terminal.RGB(red: 0, green: 0, blue: 0),
        ansi: Array(repeating: Terminal.RGB(red: 0, green: 0, blue: 0), count: 16)
    )
    return terminal
}
