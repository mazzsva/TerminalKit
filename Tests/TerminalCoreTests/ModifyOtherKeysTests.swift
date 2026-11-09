import Testing

@testable import TerminalCore

struct ModifyOtherKeysTests {
    @Test func ignoresTheKittyKeyboardSequences() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[?u\u{1B}[>1u\u{1B}[=1;1u\u{1B}[<u\u{1B}[?u\u{1B}[c") == "\u{1B}[?1;2c")
    }

    @Test func setsTheModifyOtherKeysLevel() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.modifyOtherKeys == 0)
        terminal.receive("\u{1B}[>4;1m")
        #expect(terminal.modifyOtherKeys == 1)
        terminal.receive("\u{1B}[>4;2m")
        #expect(terminal.modifyOtherKeys == 2)
        terminal.receive("\u{1B}[>1;0m\u{1B}[>0;1m\u{1B}[>;1m\u{1B}[>n\u{1B}[>2n\u{1B}[?4m")
        #expect(terminal.modifyOtherKeys == 2)
        for reset in [
            "\u{1B}[>4m", "\u{1B}[>4;0m", "\u{1B}[>m", "\u{1B}[>4n", "\u{1B}[>4;2n", "\u{1B}[>4;3m", "\u{1B}[>4;9m",
        ] {
            terminal.receive("\u{1B}[>4;2m" + reset)
            #expect(terminal.modifyOtherKeys == 0)
        }
    }

    @Test func clearsTheModifyOtherKeysLevelOnReset() {
        for reset in ["\u{1B}c", "\u{1B}[!p"] {
            var terminal = Terminal(columns: 4, rows: 2)
            terminal.receive("\u{1B}[>4;2m\u{1B}[?1049h" + reset)
            #expect(terminal.modifyOtherKeys == 0)
        }
    }
}
