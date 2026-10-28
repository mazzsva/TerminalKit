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
        #expect(other.graphemes.count == 1)
        #expect(other.character(of: other.screen[0][0]) == "e\u{301}")
        #expect(full.graphemes.count <= full.graphemes.capacity)
    }

    @Test func compactsTheTableWhenItIsFull() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.graphemes = Terminal.Graphemes(capacity: 128)
        terminal.receive(clusters(count: 200))
        terminal.receive("\u{1B}[3J\u{1B}[2J\u{1B}[H" + String(repeating: "z\u{20D0}", count: 3))
        #expect(text(terminal.screen, in: terminal).first?.hasSuffix("z\u{20D0}") == true)
        #expect(terminal.graphemes.count < 8)
    }

    @Test func keepsTheLiveCharactersThroughACompaction() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.graphemes = Terminal.Graphemes(capacity: 128)
        terminal.receive("a\u{301}\u{302}\r\nb\u{303}\r\n\r\n\r\n")
        terminal.receive("c\u{304}\u{305} d\u{306}\u{1B}[?1049h")
        terminal.receive(clusters(count: 300))
        terminal.receive("\u{1B}[2J\u{1B}[He\u{307}")
        #expect(terminal.character(of: terminal.screen[0][0]) == "e\u{307}")
        terminal.receive("\u{1B}[?1049l")
        #expect(text(terminal.scrollback, in: terminal).prefix(2) == ["a\u{301}\u{302}", "b\u{303}"])
        #expect(text(terminal.screen, in: terminal).last == "c\u{304}\u{305} d\u{306}")
    }

    @Test func keepsTheMarksThatFitWhenEveryCharacterIsInUse() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.graphemes = Terminal.Graphemes(capacity: 64)
        let text = clusters(count: 100)
        terminal.receive(text)
        let shown = (terminal.scrollback + terminal.screen).flatMap { $0 }.filter { $0.width > 0 && !$0.isBlank }
            .map(terminal.character(of:))
        let expected = Array(text)
        #expect(shown.count == expected.count)
        #expect(zip(shown, expected).allSatisfy { $1.unicodeScalars.starts(with: $0.unicodeScalars) })
        #expect(zip(shown, expected).filter { $0 == $1 }.count >= 60)
        #expect(terminal.graphemes.count <= 64)
    }

    @Test func keepsAnEmojiInItsOwnCellWhenEveryCharacterIsInUse() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.graphemes = Terminal.Graphemes(capacity: 64)
        terminal.receive(clusters(count: 100) + "\r\n\u{1F44D}\u{1F3FD}\u{1F1FA}\u{1F1F8}x")
        #expect(terminal.screen[1].prefix(7).map(\.width) == [2, 0, 2, 0, 1, 1, 1])
        #expect(
            terminal.screen[1].prefix(7).map(terminal.character(of:)) == [
                "\u{1F44D}", " ", "\u{1F3FD}", " ", "\u{1F1FA}", "\u{1F1F8}", "x",
            ])
    }

    @Test func waitsLongerAfterACompactionThatFreesNothing() {
        var graphemes = Terminal.Graphemes(capacity: 64)
        let characters = Array(clusters(count: 1_000))
        var compactions = 0
        for character in characters {
            if graphemes.needsCompaction(for: character) {
                _ = graphemes.compact(keeping: Array(repeating: true, count: graphemes.count))
                compactions += 1
            }
            _ = graphemes.cell(Terminal.Cell(), with: character)
        }
        #expect(graphemes.count == 64)
        #expect((5 ... 20).contains(compactions))
        graphemes.resetCompactionInterval()
        #expect(graphemes.needsCompaction(for: "z\u{20D0}"))
        _ = graphemes.compact(keeping: Array(repeating: false, count: graphemes.count))
        for character in characters.prefix(64) {
            _ = graphemes.cell(Terminal.Cell(), with: character)
        }
        _ = graphemes.cell(Terminal.Cell(), with: "y\u{20D0}")
        #expect(graphemes.needsCompaction(for: "z\u{20D0}"))
    }

    @Test(arguments: [2, 3])
    func keepsTheUsedCharactersWhenItCompactsALargeTable(keepingEvery stride: Int) {
        var graphemes = Terminal.Graphemes()
        let characters = Array(clusters(count: graphemes.capacity))
        var lines = [Terminal.Line(characters.map { graphemes.cell(Terminal.Cell(), with: $0) })]
        let used = characters.indices.map { $0.isMultiple(of: stride) }
        let newIndices = graphemes.compact(keeping: used)
        Terminal.Graphemes.remapIndices(in: &lines, with: newIndices)
        let kept = characters.indices.filter { used[$0] }
        #expect(graphemes.count == kept.count)
        #expect(kept.allSatisfy { graphemes.character(of: lines[0][$0]) == characters[$0] })
        #expect(kept.allSatisfy { graphemes.cell(Terminal.Cell(), with: characters[$0]) == lines[0][$0] })
        let added = graphemes.cell(Terminal.Cell(), with: characters[1])
        #expect(graphemes.character(of: added) == characters[1])
        #expect(graphemes.count == kept.count + 1)
    }

    @Test func keepsANewCharacterAfterTheScrollbackIsCleared() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.graphemes = Terminal.Graphemes(capacity: 128)
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

    @Test func keepsTheScalarsOfCanonicallyEquivalentCharactersThroughACompaction() {
        var graphemes = Terminal.Graphemes(capacity: 8)
        let pair: [Character] = ["e\u{323}\u{301}", "e\u{301}\u{323}"]
        for character in ["a\u{301}", "b\u{301}", "c\u{301}"] + pair {
            _ = graphemes.cell(Terminal.Cell(), with: character)
        }
        for used in [[false, false, false, true, true], [true, false, true]] {
            _ = graphemes.compact(keeping: used)
            for character in pair {
                let cell = graphemes.cell(Terminal.Cell(), with: character)
                #expect(Array(graphemes.character(of: cell).unicodeScalars) == Array(character.unicodeScalars))
            }
            _ = graphemes.cell(Terminal.Cell(), with: "c\u{301}")
        }
    }

    @Test func compactsTheTableForACanonicallyEquivalentCharacter() {
        var graphemes = Terminal.Graphemes(capacity: 1)
        _ = graphemes.cell(Terminal.Cell(), with: "e\u{323}\u{301}")
        #expect(graphemes.needsCompaction(for: "e\u{301}\u{323}"))
    }

    @Test(arguments: 0 ..< 40)
    func matchesATerminalWithALargeTable(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed))
        var small = Terminal(columns: 8, rows: 5)
        small.graphemes = Terminal.Graphemes(capacity: 512)
        var large = Terminal(columns: 8, rows: 5)
        let pool = Array(clusters(count: 3_000))
        for step in 0 ..< 600 {
            var input = ""
            switch Int.random(in: 0 ..< 20, using: &generator) {
            case 0:
                input = "\r\n"
            case 1:
                input = "\u{1B}[?1049h"
            case 2:
                input = "\u{1B}[?1049l"
            case 3:
                input = "\u{1B}[2J"
            case 4:
                let columns = Int.random(in: 1 ... 12, using: &generator)
                let rows = Int.random(in: 1 ... 6, using: &generator)
                small.resize(columns: columns, rows: rows)
                large.resize(columns: columns, rows: rows)
            case 5:
                input =
                    "\u{1B}[\(Int.random(in: 1 ... 5, using: &generator));\(Int.random(in: 1 ... 8, using: &generator))H"
            case 6:
                input = "中\u{301}"
            default:
                input = String(
                    (0 ..< Int.random(in: 1 ... 6, using: &generator))
                        .map { _ in pool.randomElement(using: &generator)! })
            }
            if step % 20 == 0 {
                input += "\u{1B}[3J"
            }
            small.receive(input)
            large.receive(input)
        }
        small.receive("\u{1B}[?1049l")
        large.receive("\u{1B}[?1049l")
        #expect(text(small.scrollback, in: small) == text(large.scrollback, in: large))
        #expect(text(small.screen, in: small) == text(large.screen, in: large))
        #expect(large.graphemes.count > small.graphemes.capacity)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &* 2_654_435_761 &+ 1
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state ^ (state >> 29)
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

private func text(_ lines: [Terminal.Line], in terminal: Terminal) -> [String] {
    lines.map { String($0.map(terminal.character(of:))).trimmingCharacters(in: .whitespaces) }
}
