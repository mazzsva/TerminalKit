import Testing

@testable import TerminalCore

struct ProcessCompletionTests {
    private static let z = String(repeating: "z", count: 30)

    @Test(arguments: [
        ("abc", ["abc", "[Process completed]"]),
        ("abc\r\n", ["abc", "", "[Process completed]"]),
        ("\u{1B}[31;42mabc", ["abc", "[Process completed]"]),
        ("\u{1B}[?25labc", ["abc", "[Process completed]"]),
        ("\u{1B}[?5habc", ["abc", "[Process completed]"]),
        ("\u{1B}(0abc", ["▒␉␌", "[Process completed]"]),
        ("abc\u{1B}[4h\u{1B}[Hxyz", ["xyzabc", "[Process completed]"]),
        ("\u{1B}[3;5r\u{1B}[5Habc", ["", "", "", "", "abc", "[Process completed]"]),
        ("abc\r\n\(z)\u{1B}[1;4H", ["abc", "[Process completed]\(z)"]),
        ("abc\r\n\(z)\u{1B}[4h\u{1B}[1;4H", ["abc", "[Process completed]\(z)"]),
    ])
    func showsTheTextAtTheStartOfTheNextRow(input: String, lines: [String]) {
        var terminal = Terminal(columns: 241, rows: 62)
        terminal.receive(input)
        terminal.completeProcess()
        #expect(text(terminal.scrollback + terminal.screen, in: terminal) == lines)
    }

    @Test func scrollsTheLastRowIntoTheScrollback() {
        var terminal = Terminal(columns: 241, rows: 62)
        terminal.receive("top\u{1B}[999;1Hbottom")
        terminal.completeProcess()
        let lines = ["top"] + Array(repeating: "", count: 60) + ["bottom", "[Process completed]"]
        #expect(text(terminal.scrollback + terminal.screen, in: terminal) == lines)
        #expect(terminal.scrollback.count == 2)
    }

    @Test func staysOnTheAlternateScreen() {
        var terminal = Terminal(columns: 241, rows: 62)
        terminal.receive("main\u{1B}[?1049halt")
        terminal.completeProcess()
        #expect(text(terminal.screen, in: terminal) == ["alt", "[Process completed]"])
        #expect(text(terminal.normalScreenLines, in: terminal) == ["main"])
    }

    @Test func scrollsTheAlternateScreenWithoutAScrollback() {
        var terminal = Terminal(columns: 241, rows: 62)
        terminal.receive("main\u{1B}[?1049htop\u{1B}[999;1Hbottom")
        terminal.completeProcess()
        let lines = Array(repeating: "", count: 59) + ["bottom", "[Process completed]"]
        #expect(text(terminal.screen, in: terminal) == lines)
        #expect(terminal.scrollback.isEmpty)
    }

    @Test func keepsTheRowLongerThanTheWidth() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("abc\r\nzzzzzzzzzz\u{1B}[1;4H")
        terminal.completeProcess()
        #expect(text(terminal.screen, in: terminal) == ["abc", "[Process completed]zzzzzzzzzz"])
        terminal.resize(columns: 40, rows: 3)
        #expect(text(terminal.screen, in: terminal) == ["abc", "[Process completed]zzzzzzzzzz"])
        terminal.resize(columns: 5, rows: 3)
        terminal.resize(columns: 1, rows: 1)
        terminal.resize(columns: 40, rows: 3)
        #expect(text(terminal.scrollback + terminal.screen, in: terminal) == ["abc", "[Process completed]zzzzzzzzzz"])
    }

    @Test(arguments: [(1, 1), (1, 3), (3, 1)])
    func showsTheTextOnATinyScreen(columns: Int, rows: Int) {
        var terminal = Terminal(columns: columns, rows: rows)
        terminal.receive("ab\u{1B}[?1049hc")
        terminal.completeProcess()
        terminal.resize(columns: columns + 1, rows: rows + 1)
        #expect(text(terminal.screen, in: terminal).joined().count <= 19 + 3)
    }
}

private func text(_ lines: some Sequence<Terminal.Line>, in terminal: Terminal) -> [String] {
    var text = lines.map { String($0.map(terminal.character(of:)).joined().reversed().drop { $0 == " " }.reversed()) }
    while text.last == "" {
        text.removeLast()
    }
    return text
}
