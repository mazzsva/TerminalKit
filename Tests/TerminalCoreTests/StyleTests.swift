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

    @Test func setsTheStandardColors() {
        var style = Terminal.Style()
        style.apply([31, 42])
        #expect(style.foreground == .indexed(1))
        #expect(style.background == .indexed(2))
        style.apply([37, 40])
        #expect(style.foreground == .indexed(7))
        #expect(style.background == .indexed(0))
    }

    @Test func setsTheBrightColors() {
        var style = Terminal.Style()
        style.apply([90, 107])
        #expect(style.foreground == .indexed(8))
        #expect(style.background == .indexed(15))
    }

    @Test func setsTheDefaultColors() {
        var style = Terminal.Style()
        style.apply([1, 31, 42])
        style.apply([39, 49])
        #expect(style.foreground == .default)
        #expect(style.background == .default)
        #expect(style.isBold)
    }

    @Test func setsThe256Colors() {
        var style = Terminal.Style()
        style.apply([38, 5, 208, 48, 5, 17])
        #expect(style.foreground == .indexed(208))
        #expect(style.background == .indexed(17))
    }

    @Test func setsTheTrueColors() {
        var style = Terminal.Style()
        style.apply([38, 2, 255, 128, 0, 48, 2, 1, 2, 3])
        #expect(style.foreground == .rgb(red: 255, green: 128, blue: 0))
        #expect(style.background == .rgb(red: 1, green: 2, blue: 3))
    }

    @Test func continuesAfterAnExtendedColor() {
        var style = Terminal.Style()
        style.apply([38, 5, 1, 1, 48, 2, 0, 0, 0, 4])
        #expect(style.isBold && style.isUnderlined)
    }

    @Test func ignoresAnIncompleteExtendedColor() {
        var style = Terminal.Style()
        style.apply([31])
        style.apply([38, 5])
        #expect(style.foreground == .indexed(1))
        style.apply([38, 2, 1, 2])
        #expect(style.foreground == .indexed(1))
        style.apply([38, 5, 256])
        #expect(style.foreground == .indexed(1))
        style.apply([38, 9, 1])
        #expect(style.foreground == .indexed(1))
    }

    @Test func erasesWithTheBackgroundColor() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("ab\u{1B}[1;31;44m\u{1B}[K")
        #expect(terminal.screen[0].map(\.style) == [Terminal.Style(), Terminal.Style()] + backgroundCells(2))
    }

    @Test func scrollsInLinesWithTheBackgroundColor() {
        var terminal = Terminal(columns: 2, rows: 1)
        terminal.receive("\u{1B}[44m\n")
        #expect(terminal.screen[0].map(\.style) == backgroundCells(2))
    }

    @Test func skipsAllValuesOfAnInvalidTrueColor() {
        var style = Terminal.Style()
        style.apply([38, 2, 300, 1, 4])
        #expect(style == Terminal.Style())
        style.apply([48, 2, 1, 300, 4, 1])
        #expect(style == Terminal.Style(isBold: true))
    }

    @Test func skipsTheUnderlineColor() {
        var style = Terminal.Style()
        style.apply([4, 31, 58, 5, 1])
        #expect(style == Terminal.Style(foreground: .indexed(1), isUnderlined: true))
        style.apply([58, 2, 0, 1, 9])
        #expect(style == Terminal.Style(foreground: .indexed(1), isUnderlined: true))
    }

    @Test func setsTheTrueColorsWithColons() {
        #expect(
            style("38:2::255:128:0;48:2:1:2:3")
                == Terminal.Style(
                    foreground: .rgb(red: 255, green: 128, blue: 0), background: .rgb(red: 1, green: 2, blue: 3)))
        #expect(
            style("38:2:1:2:3;48:2::4:5:6")
                == Terminal.Style(
                    foreground: .rgb(red: 1, green: 2, blue: 3), background: .rgb(red: 4, green: 5, blue: 6)))
    }

    @Test func setsThe256ColorsWithColons() {
        #expect(style("38:5:208;48:5:17") == Terminal.Style(foreground: .indexed(208), background: .indexed(17)))
    }

    @Test(arguments: 1 ... 5)
    func treatsEachUnderlineStyleAsUnderline(underline: Int) {
        #expect(style("4:\(underline)") == Terminal.Style(isUnderlined: true))
    }

    @Test func clearsTheUnderlineWithAColon() {
        #expect(style("1;4;4:0") == Terminal.Style(isBold: true))
    }

    @Test func appliesAMixedSequenceWithColons() {
        #expect(
            style("1;38:2::10:20:30;4:3")
                == Terminal.Style(foreground: .rgb(red: 10, green: 20, blue: 30), isBold: true, isUnderlined: true))
    }

    @Test func skipsTheUnderlineColorWithColons() {
        #expect(style("58:2::255:0:0;1;58:5:1;4") == Terminal.Style(isBold: true, isUnderlined: true))
        #expect(style("58:2::255:0:0") == Terminal.Style())
    }

    @Test func ignoresUnknownSubparameters() {
        #expect(
            style("38:9:1;3;48:2:1:2;9;1:31;38:5:1:2;48:5:1:2;48:5:300;4:3:1;4:6")
                == Terminal.Style(isBold: true, isItalic: true, isStrikethrough: true))
    }

    @Test func printsWithTheCurrentStyle() {
        var terminal = Terminal(columns: 4, rows: 1)
        terminal.receive("a\u{1B}[1mb\u{1B}[mc")
        #expect(terminal.screen[0].prefix(3).map(\.style.isBold) == [false, true, false])
    }
}

private func style(_ parameters: String) -> Terminal.Style {
    var terminal = Terminal(columns: 1, rows: 1)
    terminal.receive("\u{1B}[\(parameters)mA")
    return terminal.screen[0][0].style
}

private func backgroundCells(_ count: Int) -> [Terminal.Style] {
    Array(repeating: Terminal.Style(background: .indexed(4)), count: count)
}
