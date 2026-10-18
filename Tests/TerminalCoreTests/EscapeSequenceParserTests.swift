import Testing

@testable import TerminalCore

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

    @Test func dispatchesControlSequences() {
        #expect(parse("\u{1B}[H") == [controlSequence(final: "H")])
        #expect(parse("\u{1B}[12;40H") == [controlSequence(parameters: [12, 40], final: "H")])
    }

    @Test func keepsEmptyParameters() {
        #expect(parse("\u{1B}[;5H") == [controlSequence(parameters: [0, 5], final: "H")])
        #expect(parse("\u{1B}[5;H") == [controlSequence(parameters: [5, 0], final: "H")])
    }

    @Test func collectsThePrivateMarker() {
        #expect(parse("\u{1B}[?1049h") == [controlSequence(privateMarker: "?", parameters: [1049], final: "h")])
    }

    @Test func collectsIntermediates() {
        #expect(parse("\u{1B}[2 q") == [controlSequence(parameters: [2], intermediates: " ", final: "q")])
    }

    @Test func limitsParameterValues() {
        #expect(parse("\u{1B}[99999999A") == [controlSequence(parameters: [65_535], final: "A")])
    }

    @Test func ignoresMalformedControlSequences() {
        #expect(parse("\u{1B}[1?hA") == [.print("A")])
        #expect(parse("\u{1B}[ 1qA") == [.print("A")])
        #expect(parse("\u{1B}[\(String(repeating: ";", count: 32))mA") == [.print("A")])
    }

    @Test func executesControlCharactersInsideControlSequences() {
        #expect(parse("\u{1B}[1\r0H") == [.execute("\r"), controlSequence(parameters: [10], final: "H")])
    }

    @Test func ignoresOperatingSystemCommands() {
        #expect(parse("\u{1B}]0;Café\nA\u{7}B") == [.print("B")])
    }

    @Test func endsOperatingSystemCommandsWithTheStringTerminator() {
        #expect(parse("\u{1B}]2;Title\u{1B}\\A") == [.escape(intermediates: "", final: "\\"), .print("A")])
    }

    @Test func cancelsOperatingSystemCommands() {
        #expect(parse("\u{1B}]0;Title\u{18}A") == [.execute("\u{18}"), .print("A")])
    }

    @Test(arguments: ["P", "X", "^", "_"])
    func ignoresStrings(introducer: String) {
        #expect(
            parse("\u{1B}\(introducer)1$q\n\u{7}\u{1B}\\A") == [.escape(intermediates: "", final: "\\"), .print("A")])
    }
}

private func parse(_ text: String) -> [EscapeSequenceParser.Action] {
    var parser = EscapeSequenceParser()
    return text.unicodeScalars.compactMap { parser.advance($0) }
}

private func controlSequence(
    privateMarker: Unicode.Scalar? = nil,
    parameters: [Int] = [],
    intermediates: String = "",
    final: Unicode.Scalar
) -> EscapeSequenceParser.Action {
    .controlSequence(
        EscapeSequenceParser.ControlSequence(
            privateMarker: privateMarker,
            parameters: parameters,
            intermediates: intermediates,
            final: final
        )
    )
}
