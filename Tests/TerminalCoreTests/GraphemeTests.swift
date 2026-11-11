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
        full.receive(clusters(count: 70_000))
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
