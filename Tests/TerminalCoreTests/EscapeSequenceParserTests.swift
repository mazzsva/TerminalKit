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
}

private func parse(_ text: String) -> [EscapeSequenceParser.Action] {
    let parser = EscapeSequenceParser()
    return parser.parse(text.unicodeScalars)
}
