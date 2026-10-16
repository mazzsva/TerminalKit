import TerminalCore
import Testing

struct UTF8DecoderTests {
    @Test func decodesASCII() {
        let decoder = UTF8Decoder()
        #expect(decoder.decode("ls -la\n".utf8) == Array("ls -la\n".unicodeScalars))
    }
}
