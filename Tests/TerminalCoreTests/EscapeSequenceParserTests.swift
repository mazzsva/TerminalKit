import Testing

@testable import TerminalCore

struct EscapeSequenceParserTests {
    @Test func printsText() {
        #expect(parse("hé") == [.print("h"), .print("é")])
    }

    @Test func executesControlCharacters() {
        #expect(parse("\r\n\u{7}") == [.execute("\r"), .execute("\n"), .execute("\u{7}")])
    }

    @Test func printsC1ControlCharacters() {
        #expect(parse("\u{7F}\u{85}") == [.print("\u{85}")])
    }

    @Test func dispatchesEscapeSequences() {
        #expect(parse("\u{1B}7") == [.escape(intermediates: "", final: "7")])
        #expect(parse("\u{1B}(B") == [.escape(intermediates: "(", final: "B")])
    }

    @Test func executesControlCharactersInsideEscapeSequences() {
        #expect(parse("\u{1B}(\r0") == [.execute("\r"), .escape(intermediates: "(", final: "0")])
    }

    @Test(arguments: ["\u{18}", "\u{1A}"])
    func ignoresACancelInASequence(cancel: String) {
        #expect(parse("\u{1B}(\(cancel)B") == [.escape(intermediates: "(", final: "B")])
        #expect(parse("\u{1B}[1\(cancel)A") == [controlSequence(parameters: [1], final: "A")])
    }

    @Test func printsANonASCIICharacterAndContinuesTheEscape() {
        #expect(parse("\u{1B}éAB") == [.print("é"), .escape(intermediates: "", final: "A"), .print("B")])
        #expect(parse("\u{1B}(éAB") == [.print("é"), .escape(intermediates: "(", final: "A"), .print("B")])
        #expect(parse("\u{1B}\u{85}7") == [.print("\u{85}"), .escape(intermediates: "", final: "7")])
    }

    @Test func printsANonASCIICharacterAndContinuesTheControlSequence() {
        #expect(parse("\u{1B}[1éA") == [.print("é"), controlSequence(parameters: [1], final: "A")])
        #expect(
            parse("\u{1B}[1 éq") == [.print("é"), controlSequence(parameters: [1], intermediates: " ", final: "q")])
    }

    @Test(arguments: ["\u{1B}", "\u{1B}(", "\u{1B}[", "\u{1B}[1", "\u{1B}[1 "])
    func endsASequenceAtDelete(sequence: String) {
        #expect(parse(sequence + "\u{7F}A") == [.print("A")])
    }

    @Test func endsASequenceAtATabAndMovesTheCursor() {
        #expect(parse("\u{1B}(\tA") == [.execute("\t"), .print("A")])
        #expect(parse("\u{1B}[1\tA") == [.execute("\t"), .print("A")])
    }

    @Test(arguments: ["#", "(", ")", "*", "+", "-", ".", "/"])
    func continuesAnEscapeAfterADesignator(intermediate: String) {
        #expect(parse("\u{1B}\(intermediate)0A") == [.escape(intermediates: intermediate, final: "0"), .print("A")])
    }

    @Test(arguments: [" ", "!", "\"", "$", "%", "&", "'", ","])
    func endsAnEscapeAtOtherIntermediates(intermediate: String) {
        #expect(parse("\u{1B}\(intermediate)0") == [.print("0")])
    }

    @Test func endsAnEscapeAtASecondIntermediate() {
        #expect(parse("\u{1B}((0") == [.print("0")])
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

    @Test func treatsAParameterOverTheLimitAsZero() {
        #expect(parse("\u{1B}[2147483647A") == [controlSequence(parameters: [2_147_483_647], final: "A")])
        #expect(parse("\u{1B}[2147483648A") == [controlSequence(parameters: [0], final: "A")])
        #expect(parse("\u{1B}[99999999999999999999A") == [controlSequence(parameters: [0], final: "A")])
    }

    @Test func joinsTheDigitsAroundAColon() {
        #expect(parse("\u{1B}[2:2H") == [controlSequence(parameters: [22], final: "H")])
        #expect(parse("\u{1B}[:2;:3H") == [controlSequence(parameters: [2, 3], final: "H")])
    }

    @Test func ignoresAMarkerAfterAParameter() {
        #expect(parse("\u{1B}[1?hA") == [.print("A")])
        #expect(parse("\u{1B}[1>cA") == [.print("A")])
    }

    @Test func endsAControlSequenceAtASecondMarker() {
        #expect(parse("\u{1B}[??1H") == [.print("1"), .print("H")])
        #expect(parse("\u{1B}[?>1H") == [.print("1"), .print("H")])
        #expect(parse("\u{1B}[?1=H") == [.print("H")])
    }

    @Test func dropsTheOtherMarkers() {
        #expect(parse("\u{1B}[=1;2H") == [controlSequence(parameters: [1, 2], final: "H")])
        #expect(parse("\u{1B}[<A") == [controlSequence(final: "A")])
        #expect(parse("\u{1B}[1=H") == [controlSequence(parameters: [1], final: "H")])
        #expect(parse("\u{1B}[=?1H") == [controlSequence(privateMarker: "?", parameters: [1], final: "H")])
        #expect(parse("\u{1B}[=>c") == [controlSequence(privateMarker: ">", final: "c")])
    }

    @Test func keepsTheOtherMarkersForTheKeyboardFlags() {
        #expect(parse("\u{1B}[=1;1u") == [controlSequence(privateMarker: "=", parameters: [1, 1], final: "u")])
        #expect(parse("\u{1B}[<u") == [controlSequence(privateMarker: "<", final: "u")])
    }

    @Test func dropsTheOtherIntermediates() {
        #expect(parse("\u{1B}[1\"A") == [controlSequence(parameters: [1], final: "A")])
        #expect(parse("\u{1B}[1/2A") == [controlSequence(parameters: [12], final: "A")])
    }

    @Test func endsAControlSequenceAtAParameterAfterAnIntermediate() {
        #expect(parse("\u{1B}[ 2H") == [.print("H")])
        #expect(parse("\u{1B}[ ?q") == [.print("q")])
    }

    @Test func printsAThirdIntermediate() {
        #expect(parse("\u{1B}[1 !!q") == [.print("!"), .print("q")])
    }

    @Test func ignoresParametersAfterThe32nd() {
        #expect(
            parse("\u{1B}[\(String(repeating: "1;", count: 40))mA")
                == [controlSequence(parameters: Array(repeating: 1, count: 32), final: "m"), .print("A")])
        #expect(
            parse("\u{1B}[\(String(repeating: "1;", count: 40))m\u{1B}[2mA")
                == [
                    controlSequence(parameters: Array(repeating: 1, count: 32), final: "m"),
                    controlSequence(parameters: [2], final: "m"), .print("A"),
                ])
    }

    @Test func executesControlCharactersInsideControlSequences() {
        #expect(parse("\u{1B}[1\r0H") == [.execute("\r"), controlSequence(parameters: [10], final: "H")])
    }

    @Test func dispatchesOperatingSystemCommands() {
        #expect(parse("\u{1B}]0;Café\nA\u{7}B") == [.operatingSystemCommand("0;CaféA"), .print("B")])
    }

    @Test func endsOperatingSystemCommandsWithTheStringTerminator() {
        #expect(
            parse("\u{1B}]2;Title\u{1B}\\A") == [
                .operatingSystemCommand("2;Title"), .escape(intermediates: "", final: "\\"), .print("A"),
            ]
        )
    }

    @Test func limitsOperatingSystemCommands() {
        let title = String(repeating: "A", count: 4_096)
        #expect(parse("\u{1B}]\(title)\u{7}") == [.operatingSystemCommand(title)])
        #expect(parse("\u{1B}]\(title)A\u{7}B") == [.print("B")])
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
