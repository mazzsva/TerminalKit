import TerminalCore
import Testing

struct EscapeSequenceParserTests {
    @Test func printsText() {
        #expect(parse("hé") == [.print("h"), .print("é")])
    }

    @Test func executesControlCharacters() {
        #expect(parse("\r\n\u{7}") == [.execute("\r"), .execute("\n"), .execute("\u{7}")])
    }

    @Test func ignoresDeleteAndC1ControlCharacters() {
        #expect(parse("\u{7F}\u{85}").isEmpty)
    }

    @Test func dispatchesEscapeSequences() {
        #expect(parse("\u{1B}7") == [.escape(intermediates: "", final: "7")])
        #expect(parse("\u{1B}(B") == [.escape(intermediates: "(", final: "B")])
    }

    @Test func executesControlCharactersInsideEscapeSequences() {
        #expect(parse("\u{1B}(\r0") == [.execute("\r"), .escape(intermediates: "(", final: "0")])
    }

    @Test func cancelsEscapeSequences() {
        #expect(parse("\u{1B}(\u{18}B") == [.execute("\u{18}"), .print("B")])
    }

    @Test func parsesEscapeSequencesAcrossReads() {
        var parser = EscapeSequenceParser()
        #expect(parser.parse("\u{1B}(".unicodeScalars).isEmpty)
        #expect(parser.parse("B".unicodeScalars) == [.escape(intermediates: "(", final: "B")])
    }
}

private func parse(_ text: String) -> [EscapeSequenceParser.Action] {
    var parser = EscapeSequenceParser()
    return parser.parse(text.unicodeScalars)
}
