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
}
