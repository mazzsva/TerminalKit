import Testing

@testable import TerminalCore

struct StyleTests {
    @Test func setsTheTextStyle() {
        var style = Terminal.Style()
        style.apply([1, 2, 3, 4, 7, 8, 9])
        #expect(style.isBold && style.isFaint && style.isItalic && style.isUnderlined)
        #expect(style.isInverse && style.isHidden && style.isStrikethrough)
    }

    @Test func clearsEachTextStyle() {
        var style = Terminal.Style()
        style.apply([1, 2, 3, 4, 7, 8, 9])
        style.apply([22, 23, 24, 27, 28, 29])
        #expect(style == Terminal.Style())
    }

    @Test func resets() {
        var style = Terminal.Style()
        style.apply([1, 4])
        style.apply([0])
        #expect(style == Terminal.Style())
        style.apply([1, 4])
        style.apply([])
        #expect(style == Terminal.Style())
    }

    @Test func appliesTheParametersInOrder() {
        var style = Terminal.Style()
        style.apply([1, 0, 4])
        #expect(!style.isBold)
        #expect(style.isUnderlined)
    }

    @Test func treatsDoubleUnderlineAsUnderline() {
        var style = Terminal.Style()
        style.apply([21])
        #expect(style.isUnderlined)
    }

    @Test func ignoresUnknownParameters() {
        var style = Terminal.Style()
        style.apply([5, 6, 25, 99, 1])
        #expect(style.isBold)
    }

    @Test func printsWithTheCurrentStyle() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a\u{1B}[1mb\u{1B}[mc".utf8)
        #expect(terminal.screen[0].prefix(3).map(\.style.isBold) == [false, true, false])
    }
}
