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

    @Test func showsTheNewScrollbackAboveTheScreenOfTheStart() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("a\r\nb\u{1B}[?2026h\r\nc\r\nd")
        #expect(lines(terminal.displayed) == ["a   ", "b   "])
        #expect(terminal.displayed.scrollback == terminal.scrollback)
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

    @Test(arguments: [
        ("", "2"), ("\u{1B}[?2026h", "1"), ("\u{1B}[?1h", "1"), ("\u{1B}[?7l", "2"), ("\u{1B}[?25l", "2"),
        ("\u{1B}[?2004h", "1"), ("\u{1B}[?1049h", "1"), ("\u{1B}[?1006h", "1"), ("\u{1B}[?1004h", "1"),
    ])
    func reportsAPrivateMode(setup: String, status: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        if !setup.isEmpty {
            terminal.receive(setup)
        }
        let mode = setup.isEmpty ? "2026" : String(setup.dropFirst(3).dropLast())
        #expect(terminal.receive("\u{1B}[?\(mode)$p") == "\u{1B}[?\(mode);\(status)$y")
    }

    @Test(arguments: [
        ("\u{1B}[?1000h", [1000: "1", 1002: "2"]), ("\u{1B}[?1002h", [1000: "2", 1002: "1"]),
        ("\u{1B}[?1003h", [1000: "2", 1002: "1", 1003: "0"]), ("\u{1B}[?47h", [47: "1", 1047: "1", 1049: "1"]),
        ("", [47: "2", 1047: "2", 1049: "2", 7: "1", 25: "1", 1: "2", 1004: "2", 9999: "0", 0: "0"]),
    ])
    func reportsTheTrackedModes(setup: String, statuses: [Int: String]) {
        var terminal = Terminal(columns: 4, rows: 1)
        if !setup.isEmpty {
            terminal.receive(setup)
        }
        for (mode, status) in statuses {
            #expect(terminal.receive("\u{1B}[?\(mode)$p") == "\u{1B}[?\(mode);\(status)$y")
        }
    }

    @Test func reportsAnANSIMode() {
        var terminal = Terminal(columns: 4, rows: 1)
        #expect(terminal.receive("\u{1B}[4$p") == "\u{1B}[4;2$y")
        #expect(terminal.receive("\u{1B}[4h\u{1B}[4$p") == "\u{1B}[4;1$y")
        #expect(terminal.receive("\u{1B}[20$p") == "\u{1B}[20;0$y")
    }

    @Test(arguments: ["\u{1B}[?2026#p", "\u{1B}[?2026$q", "\u{1B}[>2026$p", "\u{1B}[?2026 p"])
    func ignoresOtherRequests(request: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        #expect(terminal.receive(request) == "")
    }
}

private func lines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { String($0.map(\.character)) }
}
