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

    @Test(arguments: ["\u{301}", "\u{200D}", "\u{FE0F}"])
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

    @Test(arguments: ["\u{FEFF}", "\u{897}", "\u{1ACF}"])
    func measuresUnknownZeroWidthCharacters(character: Unicode.Scalar) {
        #expect(character.width == 0)
    }
}
