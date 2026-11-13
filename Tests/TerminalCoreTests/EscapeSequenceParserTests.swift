import Testing

@testable import TerminalCore

struct EscapeSequenceParserTests {
    @Test func printsText() {
        #expect(parse("hé") == [.print("h"), .print("é")])
    }

    @Test func executesControlCharacters() {
        #expect(parse("\r\n\u{7}") == [.execute("\r"), .execute("\n"), .execute("\u{7}")])
    }

    @Test func dispatchesEscapeSequences() {
        #expect(parse("\u{1B}7") == [.escape(intermediates: "", final: "7")])
        #expect(parse("\u{1B}(B") == [.escape(intermediates: "(", final: "B")])
    }

    @Test func executesControlCharactersInsideEscapeSequences() {
        #expect(parse("\u{1B}(\r0") == [.execute("\r"), .escape(intermediates: "(", final: "0")])
    }

    @Test func ignoresDeleteInASequence() {
        #expect(parse("\u{1B}(\u{7F}A") == [.escape(intermediates: "(", final: "A")])
        #expect(parse("\u{1B}[1\u{7F}A") == [controlSequence(parameters: [1], final: "A")])
        #expect(parse("\u{1B}]0;a\u{7F}b\u{7}") == [.operatingSystemCommand("0;ab")])
    }

    @Test func executesATabAndContinuesTheSequence() {
        #expect(parse("\u{1B}(\tA") == [.execute("\t"), .escape(intermediates: "(", final: "A")])
        #expect(parse("\u{1B}[1\tA") == [.execute("\t"), controlSequence(parameters: [1], final: "A")])
    }

    @Test(arguments: [" ", "!", "\"", "$", "%", "&", "'", ","])
    func collectsOtherIntermediatesInAnEscape(intermediate: String) {
        #expect(parse("\u{1B}\(intermediate)0A") == [.escape(intermediates: intermediate, final: "0"), .print("A")])
    }

    @Test func collectsASecondIntermediateInAnEscape() {
        #expect(parse("\u{1B}((0A") == [.escape(intermediates: "((", final: "0"), .print("A")])
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

    @Test func collectsTheFirstSubparameter() {
        #expect(parse("\u{1B}[4:3;31m") == [controlSequence(parameters: [4, 31], final: "m", subparameters: [0: 3])])
        #expect(
            parse("\u{1B}[:2;:3H") == [controlSequence(parameters: [0, 0], final: "H", subparameters: [0: 2, 1: 3])])
        #expect(parse("\u{1B}[38:2::255m") == [controlSequence(parameters: [38], final: "m", subparameters: [0: 2])])
    }

    @Test func ignoresASecondMarker() {
        #expect(parse("\u{1B}[??1HA") == [.print("A")])
        #expect(parse("\u{1B}[?>1HA") == [.print("A")])
        #expect(parse("\u{1B}[?1=HA") == [.print("A")])
        #expect(parse("\u{1B}[=?1HA") == [.print("A")])
    }

    @Test func collectsTheOtherMarkers() {
        #expect(parse("\u{1B}[=1;2H") == [controlSequence(privateMarker: "=", parameters: [1, 2], final: "H")])
        #expect(parse("\u{1B}[<A") == [controlSequence(privateMarker: "<", final: "A")])
        #expect(parse("\u{1B}[=c") == [controlSequence(privateMarker: "=", final: "c")])
    }

    @Test func collectsTheOtherIntermediates() {
        #expect(parse("\u{1B}[1\"A") == [controlSequence(parameters: [1], intermediates: "\"", final: "A")])
        #expect(parse("\u{1B}[0%m") == [controlSequence(parameters: [0], intermediates: "%", final: "m")])
        #expect(
            parse("\u{1B}[?2026$p")
                == [controlSequence(privateMarker: "?", parameters: [2026], intermediates: "$", final: "p")])
    }

    @Test func ignoresAParameterAfterAnIntermediate() {
        #expect(parse("\u{1B}[ 2HA") == [.print("A")])
        #expect(parse("\u{1B}[ ?qA") == [.print("A")])
        #expect(parse("\u{1B}[1/2AB") == [.print("B")])
    }

    @Test func limitsIntermediates() {
        #expect(parse("\u{1B}[1 !!q") == [controlSequence(parameters: [1], intermediates: " !", final: "q")])
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
        #expect(
            parse("\u{1B}]0;Café\n\tA\u{7}B") == [.operatingSystemCommand("0;CaféA"), .print("B")])
    }

    @Test func endsOperatingSystemCommandsWithTheStringTerminator() {
        #expect(parse("\u{1B}]2;Title\u{1B}\\A") == [.operatingSystemCommand("2;Title"), .print("A")])
        #expect(parse("\u{1B}]112\u{1B}\\") == [.operatingSystemCommand("112")])
    }

    @Test func limitsOperatingSystemCommands() {
        let title = String(repeating: "A", count: 999_998)
        #expect(parse("\u{1B}]2;\(title)\u{7}") == [.operatingSystemCommand("2;\(title)")])
        #expect(parse("\u{1B}]2;\(title)A\u{7}B") == [.print("B")])
    }

    @Test func cancelsAnOperatingSystemCommandAtAnEscape() {
        #expect(parse("\u{1B}]0;Title\u{1B}xA") == [.escape(intermediates: "", final: "x"), .print("A")])
        #expect(parse("\u{1B}]0;abc\u{1B}[31m") == [controlSequence(parameters: [31], final: "m")])
    }

    @Test(arguments: ["", "A2", "2:1", " 2", "2?", "+2"])
    func ignoresAnOperatingSystemCommandWithAnotherNumber(number: String) {
        #expect(parse("\u{1B}]\(number);A\u{7}B") == [.print("B")])
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
    final: Unicode.Scalar,
    subparameters: [Int: Int] = [:]
) -> EscapeSequenceParser.Action {
    .controlSequence(
        EscapeSequenceParser.ControlSequence(
            privateMarker: privateMarker,
            parameters: parameters,
            intermediates: intermediates,
            final: final,
            subparameters: subparameters
        )
    )
}
