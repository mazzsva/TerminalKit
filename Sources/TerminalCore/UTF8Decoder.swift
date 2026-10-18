struct UTF8Decoder {
    private var incompleteBytes: [UInt8] = []

    mutating func decode(_ bytes: [UInt8]) -> String.UnicodeScalarView {
        let bytes = incompleteBytes + bytes
        let end = Self.endOfCompleteSequences(in: bytes)
        incompleteBytes = Array(bytes[end...])
        return String(decoding: bytes[..<end], as: UTF8.self).unicodeScalars
    }

    private static func endOfCompleteSequences(in bytes: [UInt8]) -> Int {
        for count in 1 ... min(3, bytes.count) where bytes[bytes.count - count] & 0xC0 != 0x80 {
            let length =
                switch bytes[bytes.count - count] {
                case 0xC2 ... 0xDF: 2
                case 0xE0 ... 0xEF: 3
                case 0xF0 ... 0xF4: 4
                default: 1
                }
            return length > count ? bytes.count - count : bytes.count
        }
        return bytes.count
    }
}
