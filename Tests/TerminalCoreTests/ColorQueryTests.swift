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
        #expect(terminal.receive("\u{1B}]10;?\u{7}") == "")
    }

    @Test func keepsTheColorsAfterAReset() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}c\u{1B}]11;?\u{7}") == "\u{1B}]11;rgb:ffff/fefe/0000\u{7}")
    }

    @Test func recordsTheChanges() {
        var terminal = coloredTerminal()
        terminal.receive("\u{1B}]12;#304050\u{7}")
        terminal.receive("\u{1B}]4;2;#506070\u{7}")
        let changes = terminal.changedColors
        #expect(changes.cursor == Terminal.RGB(red: 0x3000, green: 0x4000, blue: 0x5000))
        #expect(changes.indexed == [2: Terminal.RGB(red: 0x5000, green: 0x6000, blue: 0x7000)])
    }

    @Test func changesTheFirstAndTheLastIndexedColor() {
        var terminal = coloredTerminal()
        terminal.receive("\u{1B}]4;0;#102030;255;#405060\u{7}")
        #expect(
            terminal.changedColors.indexed == [
                0: Terminal.RGB(red: 0x1000, green: 0x2000, blue: 0x3000),
                255: Terminal.RGB(red: 0x4000, green: 0x5000, blue: 0x6000),
            ])
    }

    @Test func clearsOnlyTheIndexedColorsOnAReset() {
        for reset in ["\u{1B}c", "\u{1B}[!p"] {
            var terminal = coloredTerminal()
            terminal.receive("\u{1B}]12;#102030\u{7}\u{1B}]4;2;#506070\u{7}" + reset)
            #expect(terminal.changedColors.indexed.isEmpty)
            #expect(terminal.changedColors.cursor != nil)
        }
    }

    @Test func resetsTheCursorColor() {
        var terminal = coloredTerminal()
        terminal.receive("\u{1B}]12;#333\u{7}\u{1B}]112\u{7}")
        #expect(terminal.changedColors.isEmpty)
    }

    @Test func ignoresTheRemovedColorCommands() {
        var terminal = coloredTerminal()
        terminal.receive("\u{1B}]4;1;#666\u{7}")
        let changes = terminal.changedColors
        let commands = [
            "4;1;?", "4;256;#111", "4;257;?", "5;0;#222", "5;1;?", "10;#333", "11;#444", "13;?", "17;#555",
            "19;?", "104", "105;0", "110", "111", "117",
        ]
        for command in commands {
            #expect(terminal.receive("\u{1B}]\(command)\u{7}") == "")
        }
        #expect(terminal.changedColors == changes)
        terminal.receive("A")
        #expect(terminal.screen[0][0] == Terminal.Cell(scalar: "A"))
    }
}

private func coloredTerminal() -> Terminal {
    var terminal = Terminal(columns: 1, rows: 1)
    terminal.defaultColors = Terminal.DefaultColors(
        foreground: Terminal.RGB(red: 0x0001, green: 0xABCD, blue: 0x1234),
        background: Terminal.RGB(red: 0xFFFF, green: 0xFEFE, blue: 0x0000),
        cursor: Terminal.RGB(red: 0, green: 0, blue: 0)
    )
    return terminal
}
