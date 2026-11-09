import Testing

@testable import TerminalCore

struct MouseTests {
    @Test(arguments: [
        ("\u{1B}[?1000h", Terminal.MouseTracking.clicks), ("\u{1B}[?1002h", .drags), ("\u{1B}[?1003h", .anyMotion),
        ("\u{1B}[?1002h\u{1B}[?1002l", .off),
    ])
    func tracksTheMouseInTheModeOfTheProcess(sequence: String, tracking: Terminal.MouseTracking) {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive(sequence)
        #expect(terminal.mouseTracking == tracking)
    }

    @Test func reportsInTheDefaultEncoding() {
        let terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.mouseReport(button: 0, column: 2, row: 1, isRelease: false) == Array("\u{1B}[M #\"".utf8))
        #expect(terminal.mouseReport(button: 4, column: 0, row: 0, isRelease: true) == Array("\u{1B}[M'!!".utf8))
    }

    @Test func clampsReportsBeyondTheDefaultEncoding() {
        let terminal = Terminal(columns: 400, rows: 400)
        let report = terminal.mouseReport(button: 0, column: 300, row: 300, isRelease: true)
        #expect(report == Array("\u{1B}[M#".utf8) + [255, 255])
        let clampedReport = terminal.mouseReport(button: 0, column: 250, row: 0, isRelease: false)
        #expect(clampedReport == Array("\u{1B}[M ".utf8) + [255, 33])
    }

    @Test func reportsInTheSGREncoding() {
        var terminal = Terminal(columns: 300, rows: 2)
        terminal.receive("\u{1B}[?1006h")
        #expect(
            terminal.mouseReport(button: 2, column: 250, row: 1, isRelease: false) == Array("\u{1B}[<2;251;2M".utf8))
        #expect(terminal.mouseReport(button: 2, column: 250, row: 1, isRelease: true) == Array("\u{1B}[<2;251;2m".utf8))
    }

    @Test func reportsInTheUTF8Encoding() {
        var terminal = Terminal(columns: 3000, rows: 2)
        terminal.receive("\u{1B}[?1005h")
        #expect(terminal.mouseReport(button: 0, column: 4, row: 2, isRelease: false) == Array("\u{1B}[M %#".utf8))
        #expect(
            terminal.mouseReport(button: 0, column: 229, row: 3, isRelease: true) == Array("\u{1B}[M#\u{106}$".utf8))
        #expect(
            terminal.mouseReport(button: 0, column: 2500, row: 0, isRelease: false) == Array("\u{1B}[M \u{7FF}!".utf8))
    }

    @Test func reportsInTheURXVTEncoding() {
        var terminal = Terminal(columns: 300, rows: 2)
        terminal.receive("\u{1B}[?1015h")
        #expect(
            terminal.mouseReport(button: 0, column: 229, row: 3, isRelease: false) == Array("\u{1B}[32;230;4M".utf8))
        #expect(terminal.mouseReport(button: 0, column: 4, row: 2, isRelease: true) == Array("\u{1B}[35;5;3M".utf8))
        #expect(terminal.mouseReport(button: 64, column: 4, row: 2, isRelease: false) == Array("\u{1B}[96;5;3M".utf8))
    }

    @Test(arguments: ["\u{1B}[?1015h\u{1B}[?1006h", "\u{1B}[?1005h\u{1B}[?1006h", "\u{1B}[?1006h\u{1B}[?1015h"])
    func prefersTheSGREncoding(modes: String) {
        var terminal = Terminal(columns: 300, rows: 2)
        terminal.receive(modes)
        #expect(terminal.mouseReport(button: 0, column: 229, row: 3, isRelease: true) == Array("\u{1B}[<0;230;4m".utf8))
    }

    @Test func turnsTheEncodingsOff() {
        var terminal = Terminal(columns: 300, rows: 2)
        terminal.receive("\u{1B}[?1005h\u{1B}[?1015h\u{1B}[?1005l\u{1B}[?1015l")
        #expect(terminal.mouseReport(button: 0, column: 4, row: 2, isRelease: false) == Array("\u{1B}[M %#".utf8))
    }
}
