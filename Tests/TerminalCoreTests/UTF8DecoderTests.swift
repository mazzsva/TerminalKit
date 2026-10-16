import TerminalCore
import Testing

struct UTF8DecoderTests {
    @Test func decodesASCII() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode("ls -la\n".utf8) == Array("ls -la\n".unicodeScalars))
    }

    @Test func decodesMultibyteSequences() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode("é€😀".utf8) == Array("é€😀".unicodeScalars))
    }

    @Test func decodesSequencesAcrossReads() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xF0, 0x9F]).isEmpty)
        #expect(decoder.decode([0x98, 0x80]) == ["😀"])
    }

    @Test func replacesInvalidBytes() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0x80, 0xC0, 0xFF]) == ["\u{FFFD}", "\u{FFFD}", "\u{FFFD}"])
    }

    @Test func replacesInterruptedSequences() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xE2, 0x82, 0x41]) == ["\u{FFFD}", "A"])
    }

    @Test func replacesOverlongSequences() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xE0, 0x80, 0xAF]) == ["\u{FFFD}", "\u{FFFD}", "\u{FFFD}"])
    }

    @Test func replacesSurrogates() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xED, 0xA0, 0x80]) == ["\u{FFFD}", "\u{FFFD}", "\u{FFFD}"])
    }

    @Test func replacesScalarsAboveTheMaximum() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xF4, 0x90, 0x80, 0x80]) == ["\u{FFFD}", "\u{FFFD}", "\u{FFFD}", "\u{FFFD}"])
    }
}
