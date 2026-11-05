import Testing

@testable import TerminalCore

struct ColorQueryTests {
    @Test func reportsTheForeground() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}]10;?\u{7}") == foregroundReply)
    }

    @Test(arguments: ["\u{7}", "\u{1B}\\"])
    func reportsTheBackgroundWithTheStringTerminator(terminator: String) {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}]11;?\(terminator)") == backgroundReply)
    }

    @Test func reportsEachSuccessiveColor() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}]10;?;?\u{7}") == foregroundReply + backgroundReply)
        #expect(terminal.receive("\u{1B}]10;rgb:0/0/0;?\u{7}") == backgroundReply)
        #expect(terminal.receive("\u{1B}]10;;?\u{7}") == backgroundReply)
        #expect(terminal.receive("\u{1B}]11;?;?\u{7}") == backgroundReply)
    }

    @Test func reportsTheSwappedColorsInReverseVideo() {
        var terminal = coloredTerminal()
        #expect(
            terminal.receive("\u{1B}[?5h\u{1B}]10;?;?\u{7}")
                == "\u{1B}]10;rgb:ffff/fefe/0000\u{1B}\\\u{1B}]11;rgb:0001/abcd/1234\u{1B}\\")
    }

    @Test func reportsTheColorsBeforeTheDeviceAttributes() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}]11;?\u{7}\u{1B}[c") == backgroundReply + "\u{1B}[?1;2c")
    }

    @Test func ignoresColorQueriesWithoutColors() {
        var terminal = Terminal(columns: 1, rows: 1)
        #expect(terminal.receive("\u{1B}]10;?\u{7}\u{1B}]11;?;?\u{7}") == "")
    }

    @Test func ignoresOtherColorCommands() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}]11;#000000\u{7}\u{1B}]11\u{7}\u{1B}]12;?\u{7}\u{1B}]4;1;?\u{7}") == "")
        #expect(terminal.receive("\u{1B}]11;?\u{7}") == backgroundReply)
    }

    @Test func keepsTheColorsAfterAReset() {
        var terminal = coloredTerminal()
        #expect(terminal.receive("\u{1B}c\u{1B}]11;?\u{7}") == backgroundReply)
    }

    @Test func ignoresTheColorSchemeQueryAndMode() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.reportedColors = colors(background: 0xFFFF)
        #expect(terminal.receive("a\u{1B}[?996n\u{1B}[996n\u{1B}[?2031hb") == "")
        terminal.reportedColors = colors(background: 0x1E1E)
        #expect(terminal.receive("") == "")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b", " ", " "])
    }
}

private let foregroundReply = "\u{1B}]10;rgb:0001/abcd/1234\u{1B}\\"
private let backgroundReply = "\u{1B}]11;rgb:ffff/fefe/0000\u{1B}\\"

private func coloredTerminal() -> Terminal {
    var terminal = Terminal(columns: 1, rows: 1)
    terminal.reportedColors = [
        Terminal.RGB(red: 0x0001, green: 0xABCD, blue: 0x1234),
        Terminal.RGB(red: 0xFFFF, green: 0xFEFE, blue: 0x0000),
    ]
    return terminal
}

private func colors(background: UInt16) -> [Terminal.RGB] {
    [
        Terminal.RGB(red: 0xFFFF - background, green: 0xFFFF - background, blue: 0xFFFF - background),
        Terminal.RGB(red: background, green: background, blue: background),
    ]
}
