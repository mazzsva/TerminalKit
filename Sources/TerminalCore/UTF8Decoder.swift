package struct UTF8Decoder: Sendable {
    private var scalar: UInt32 = 0
    private var remaining = 0

    package init() {}

    package mutating func decode(_ bytes: some Sequence<UInt8>) -> [Unicode.Scalar] {
        var scalars: [Unicode.Scalar] = []
        for byte in bytes {
            if remaining > 0 {
                if byte & 0xC0 == 0x80 {
                    scalar = scalar << 6 | UInt32(byte & 0x3F)
                    remaining -= 1
                    if remaining == 0 {
                        scalars.append(Unicode.Scalar(scalar) ?? .replacement)
                    }
                    continue
                }
                remaining = 0
                scalars.append(.replacement)
            }

            switch byte {
            case 0x00 ... 0x7F:
                scalars.append(Unicode.Scalar(byte))
            case 0xC2 ... 0xDF:
                begin(byte & 0x1F, remaining: 1)
            case 0xE0 ... 0xEF:
                begin(byte & 0x0F, remaining: 2)
            case 0xF0 ... 0xF4:
                begin(byte & 0x07, remaining: 3)
            default:
                scalars.append(.replacement)
            }
        }
        return scalars
    }

    private mutating func begin(_ bits: UInt8, remaining: Int) {
        scalar = UInt32(bits)
        self.remaining = remaining
    }
}

extension Unicode.Scalar {
    static let replacement: Unicode.Scalar = "\u{FFFD}"
}
