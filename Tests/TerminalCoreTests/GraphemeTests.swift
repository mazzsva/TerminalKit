import Testing

@testable import TerminalCore

@Suite(.timeLimit(.minutes(1)))
struct GraphemeTests {
    @Test func keepsNewGraphemesAfterManyOthers() {
        var terminal = Terminal(columns: 80, rows: 24)
        terminal.receive(clusters(count: 64_960))
        terminal.receive("\u{1B}[H\u{1B}[2Jz\u{20D0}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "z\u{20D0}")
    }

    @Test func keepsATableForEachTerminal() {
        var full = Terminal(columns: 80, rows: 24)
        full.receive(clusters(count: 60_000))
        var other = Terminal(columns: 80, rows: 24)
        other.receive("e\u{301}")
        #expect(other.character(of: other.screen[0][0]) == "e\u{301}")
        #expect(full.character(of: full.screen[0][0]).unicodeScalars.count > 1)
    }

    @Test func keepsANewCharacterAfterTheScrollbackIsCleared() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive(clusters(count: 1_000))
        terminal.receive("\u{1B}[3J\u{1B}[2J\u{1B}[H" + "z\u{20D0}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "z\u{20D0}")
    }

    @Test func keepsTheTableAfterAReset() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("a\u{301}\r\n\r\n\u{1B}c")
        #expect(text(terminal.scrollback, in: terminal) == ["a\u{301}"])
    }

    @Test func keepsEachCharacterWhenTheTableIsBuiltAgain() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("a\u{301}\r\n\r\n\r\n\u{1B}[?1049hb\u{302}\u{1B}[?2026h\u{1B}[H")
        terminal.receive(clusters(count: 70_000))
        #expect(text(terminal.scrollback.prefix(1), in: terminal) == ["a\u{301}"])
        #expect(text(terminal.displayed.screen.prefix(1), in: terminal.displayed) == ["b\u{302}"])
        let last = Array(clusters(count: 70_000)).suffix(30).map(String.init)
        #expect(terminal.screen.flatMap { $0.map(terminal.character(of:)) } == last)
    }

    @Test func keepsTheMarksThatACellHasWhenTheTableIsFull() {
        var terminal = Terminal(columns: 80, rows: 24)
        var text = ""
        for index in 0 ..< 70_000 {
            for value in [0x61 + index / 12_544, 0x300 + index / 112 % 112, 0x300 + index % 112] {
                text.unicodeScalars.append(Unicode.Scalar(value)!)
            }
        }
        terminal.receive(text)
        terminal.receive("\u{1B}[2J\u{1B}[Hx\u{330}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "x")
        terminal.receive("\u{1B}[3J\u{1B}cx\u{330}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "x\u{330}")
    }

    @Test func keepsACharacterThatAnotherCellSharesWhenTheOtherCellGetsAMark() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("a\u{301}a\u{301}\u{302}")
        #expect(terminal.screen[0].prefix(2).map(terminal.character(of:)) == ["a\u{301}", "a\u{301}\u{302}"])
    }

    @Test func keepsTheCharacterOfTheSnapshotWhenItsCellGetsAMark() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("a\u{301}\u{1B}[?2026h\u{302}")
        #expect(terminal.displayed.character(of: terminal.displayed.screen[0][0]) == "a\u{301}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "a\u{301}\u{302}")
    }

    @Test func keepsTheScalarsOfCanonicallyEquivalentCharacters() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("e\u{323}\u{301} e\u{301}\u{323} e\u{323}\u{301}")
        #expect(Array(terminal.character(of: terminal.screen[0][0]).unicodeScalars) == ["e", "\u{323}", "\u{301}"])
        #expect(Array(terminal.character(of: terminal.screen[0][2]).unicodeScalars) == ["e", "\u{301}", "\u{323}"])
        #expect(Array(terminal.character(of: terminal.screen[0][4]).unicodeScalars) == ["e", "\u{323}", "\u{301}"])
    }
}

private func clusters(count: Int) -> String {
    var text = ""
    var made = 0
    for base in Array(0x61 ... 0x7A) + Array(0x41 ... 0x5A) {
        for first in 0x300 ... 0x314 {
            for second in 0x300 ... 0x314 {
                for third in 0x300 ... 0x314 {
                    guard made < count else {
                        return text
                    }
                    for value in [base, first, second, third] {
                        text.unicodeScalars.append(Unicode.Scalar(value)!)
                    }
                    made += 1
                }
            }
        }
    }
    return text
}

private func text(_ lines: some Sequence<Terminal.Line>, in terminal: Terminal) -> [String] {
    lines.map { $0.map(terminal.character(of:)).joined().trimmingCharacters(in: .whitespaces) }
}
