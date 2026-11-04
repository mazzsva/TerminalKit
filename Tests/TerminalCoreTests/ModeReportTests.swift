import Testing

@testable import TerminalCore

struct ModeReportTests {
    @Test(arguments: [
        ("\u{1B}[?1h", "1"), ("\u{1B}[?7l", "2"), ("\u{1B}[?25l", "2"), ("\u{1B}[?2004h", "1"),
        ("\u{1B}[?1049h", "1"), ("\u{1B}[?1006h", "1"), ("\u{1B}[?1004h", "1"), ("\u{1B}[?5h", "1"),
    ])
    func reportsAPrivateMode(setup: String, status: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive(setup)
        let mode = String(setup.dropFirst(3).dropLast())
        #expect(terminal.receive("\u{1B}[?\(mode)$p") == "\u{1B}[?\(mode);\(status)$y")
    }

    @Test(arguments: [
        ("\u{1B}[?1000h", [1000: "1", 1002: "2"]), ("\u{1B}[?1002h", [1000: "2", 1002: "1", 1003: "2"]),
        ("\u{1B}[?1003h", [1000: "2", 1002: "2", 1003: "1"]), ("\u{1B}[?47h", [47: "1", 1047: "1", 1049: "1"]),
        ("", [47: "2", 1047: "2", 1049: "2", 7: "1", 25: "1", 1: "2", 1004: "2", 5: "2", 9999: "0", 0: "0"]),
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
