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

    @Test func reportsNothingBeyondTheDefaultEncoding() {
        let terminal = Terminal(columns: 300, rows: 2)
        #expect(terminal.mouseReport(button: 0, column: 223, row: 0, isRelease: false) == nil)
    }

    @Test func reportsInTheSGREncoding() {
        var terminal = Terminal(columns: 300, rows: 2)
        terminal.receive("\u{1B}[?1006h")
        #expect(
            terminal.mouseReport(button: 2, column: 250, row: 1, isRelease: false) == Array("\u{1B}[<2;251;2M".utf8))
        #expect(terminal.mouseReport(button: 2, column: 250, row: 1, isRelease: true) == Array("\u{1B}[<2;251;2m".utf8))
    }
}
