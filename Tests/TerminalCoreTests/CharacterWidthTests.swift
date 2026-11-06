import Foundation
import Testing

@testable import TerminalCore

struct CharacterWidthTests {
    @Test(arguments: ["a", "é", "Ω", "─", "ｱ"])
    func measuresNarrowCharacters(character: Unicode.Scalar) {
        #expect(character.width == 1)
    }

    @Test(arguments: ["中", "한", "ア", "Ａ", "😀", "🫨", "⌚"])
    func measuresWideCharacters(character: Unicode.Scalar) {
        #expect(character.width == 2)
    }

    @Test(arguments: ["\u{301}", "\u{FE0F}", "\u{1160}", "\u{2066}", "\u{F870}", "\u{897}"])
    func measuresZeroWidthCharacters(character: Unicode.Scalar) {
        #expect(character.width == 0)
    }

    @Test(arguments: ["\u{AD}", "\u{1C89}"])
    func measuresUnknownNarrowCharacters(character: Unicode.Scalar) {
        #expect(character.width == 1)
    }

    @Test(arguments: ["\u{1FAE9}", "\u{1F6D8}", "\u{2FFC}", "\u{31E4}", "\u{31EF}", "\u{2EBF0}", "\u{323B0}"])
    func measuresUnknownWideCharacters(character: Unicode.Scalar) {
        #expect(character.width == 2)
    }

    @Test(arguments: ["\u{200B}", "\u{200D}", "\u{FEFF}", "\u{20E3}", "\u{E0061}", "\u{903}", "\u{1F1FA}"])
    func measuresOneColumnForTheCharactersThatJoinInOtherTerminals(character: Unicode.Scalar) {
        #expect(character.width == 1)
    }

    @Test func matchesTheWidthOfEveryScalarInTerminalApp() throws {
        let url = try #require(
            Bundle.module.url(forResource: "widths", withExtension: "txt", subdirectory: "Recordings")
        )
        var checked = 0
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: " ")
            let first = try #require(UInt32(fields[0], radix: 16))
            let last = try #require(UInt32(fields[1], radix: 16))
            let width = try #require(Int(fields[2]))
            for value in first ... last {
                if let scalar = Unicode.Scalar(value), scalar.width != width {
                    Issue.record("U+\(String(value, radix: 16)) is \(scalar.width), not \(width)")
                }
                checked += 1
            }
        }
        #expect(checked == 0x11_0000 - 0x80)
    }
}
