import Testing

@testable import TerminalCore

struct CellTests {
    @Test func storesACharacterOfManyScalars() {
        var graphemes = Terminal.Graphemes()
        let cell = graphemes.cell(Terminal.Cell(), with: "👍🏽")
        #expect(graphemes.character(of: cell) == "👍🏽")
        #expect(!cell.isASCII)
        #expect(!cell.isSpace)
    }

    @Test func comparesCharactersOfManyScalars() {
        var graphemes = Terminal.Graphemes()
        let cell = graphemes.cell(Terminal.Cell(), with: "e\u{301}")
        let other = graphemes.cell(Terminal.Cell(scalar: "x"), with: "e\u{301}")
        #expect(cell == other)
        #expect(graphemes.count == 1)
    }

    @Test func storesACharacterOfOneScalarInTheCell() {
        var graphemes = Terminal.Graphemes()
        let cell = graphemes.cell(Terminal.Cell(), with: "é")
        #expect(graphemes.character(of: cell) == "é")
        #expect(cell == Terminal.Cell(scalar: "é"))
        #expect(graphemes.count == 0)
    }

    @Test func showsPaddingAsABlank() {
        #expect(Terminal.Graphemes().character(of: .padding) == " ")
        #expect(Terminal.Cell.padding.isBlank)
        #expect(Terminal.Cell.padding.isSpace)
        #expect(Terminal.Cell.padding != Terminal.Cell())
    }

    @Test(arguments: [(" ", true, true), ("a", false, true), ("~", false, true), ("é", false, false)])
    func findsSpacesAndASCII(scalar: Unicode.Scalar, isSpace: Bool, isASCII: Bool) {
        #expect(Terminal.Cell(scalar: scalar).isSpace == isSpace)
        #expect(Terminal.Cell(scalar: scalar).isASCII == isASCII)
    }

    @Test func storesOnlyPlainValues() {
        #expect(_isPOD(Terminal.Cell.self))
    }
}
