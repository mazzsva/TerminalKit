import Testing

@testable import TerminalCore

struct ModeReportTests {
    @Test(arguments: ["\u{1B}[4$p", "\u{1B}[20$p"])
    func ignoresModeRequests(request: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        #expect(terminal.receive("a\(request)b") == "")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "b", " ", " "])
    }

    @Test(arguments: [
        "\u{1B}[?2026$p", "\u{1B}[?1$p", "\u{1B}[?2004h\u{1B}[?2004$p", "\u{1B}[?1049h\u{1B}[?1049l\u{1B}[?1049$p",
        "\u{1B}[?2031$p", "\u{1B}[?9999$p", "\u{1B}[?2026#p", "\u{1B}[>2026$p", "\u{1B}[?2026 p",
    ])
    func printsTheFinalOfAMarkedModeRequest(request: String) {
        var terminal = Terminal(columns: 4, rows: 1)
        #expect(terminal.receive("a\(request)b") == "")
        #expect(terminal.screen[0].map(terminal.character(of:)) == ["a", "p", "b", " "])
    }
}
