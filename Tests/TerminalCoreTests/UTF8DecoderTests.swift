import Testing

@testable import TerminalCore

struct UTF8DecoderTests {
    @Test func decodesASCII() {
        var decoder = UTF8Decoder()
        #expect(Array(decoder.decode(Array("ls -la\n".utf8))) == Array("ls -la\n".unicodeScalars))
    }

    @Test func decodesMultibyteSequences() {
        var decoder = UTF8Decoder()
        #expect(Array(decoder.decode(Array("é€😀".utf8))) == Array("é€😀".unicodeScalars))
    }

    @Test func decodesSequencesAcrossReads() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xF0, 0x9F]).isEmpty)
        #expect(Array(decoder.decode([0x98, 0x80])) == ["😀"])
    }

    @Test func replacesInvalidBytes() {
        var decoder = UTF8Decoder()
        #expect(Array(decoder.decode([0x41, 0x80, 0xC0, 0xFF])) == ["A", "\u{FFFD}", "\u{FFFD}", "\u{FFFD}"])
    }

    @Test func replacesInterruptedSequences() {
        var decoder = UTF8Decoder()
        #expect(decoder.decode([0xE2, 0x82]).isEmpty)
        #expect(Array(decoder.decode([0x41])) == ["\u{FFFD}", "A"])
    }

    @Test(arguments: [[0xE0, 0x80, 0xAF], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80]] as [[UInt8]])
    func replacesInvalidSequences(bytes: [UInt8]) {
        var decoder = UTF8Decoder()
        #expect(Array(decoder.decode(bytes)) == Array(repeating: "\u{FFFD}", count: bytes.count))
    }
}
