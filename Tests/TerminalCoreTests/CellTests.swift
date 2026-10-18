import Testing

@testable import TerminalCore

struct CellTests {
    @Test func storesACharacterOfManyScalars() {
        var cell = Terminal.Cell()
        cell.character = "👍🏽"
        #expect(cell.character == "👍🏽")
    }

    @Test func comparesCharactersOfManyScalars() {
        var cell = Terminal.Cell()
        var other = Terminal.Cell(scalar: "x")
        cell.character = "e\u{301}"
        other.character = "e\u{301}"
        #expect(cell == other)
    }

    @Test func storesOnlyPlainValues() {
        #expect(_isPOD(Terminal.Cell.self))
    }
}
