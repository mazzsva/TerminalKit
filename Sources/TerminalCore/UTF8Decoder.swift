package struct UTF8Decoder: Sendable {
    package init() {}

    package func decode(_ bytes: some Sequence<UInt8>) -> [Unicode.Scalar] {
        bytes.map { byte in
            byte < 0x80 ? Unicode.Scalar(byte) : .replacement
        }
    }
}

extension Unicode.Scalar {
    static let replacement: Unicode.Scalar = "\u{FFFD}"
}
