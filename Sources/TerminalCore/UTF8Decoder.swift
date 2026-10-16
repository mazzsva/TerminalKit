package struct UTF8Decoder: Sendable {
    private var scalar: UInt32 = 0
    private var remaining = 0
    private var continuation: ClosedRange<UInt8> = 0x80 ... 0xBF

    package init() {}

    package mutating func decode(_ bytes: some Sequence<UInt8>) -> [Unicode.Scalar] {
        var scalars: [Unicode.Scalar] = []
        for byte in bytes {
            if remaining > 0 {
                if continuation.contains(byte) {
                    scalar = scalar << 6 | UInt32(byte & 0x3F)
                    remaining -= 1
                    continuation = 0x80 ... 0xBF
                    if remaining == 0 {
                        scalars.append(Unicode.Scalar(scalar) ?? .replacement)
                    }
                    continue
                }
                remaining = 0
                continuation = 0x80 ... 0xBF
                scalars.append(.replacement)
            }

            switch byte {
            case 0x00 ... 0x7F:
                scalars.append(Unicode.Scalar(byte))
            case 0xC2 ... 0xDF:
                begin(byte & 0x1F, remaining: 1)
            case 0xE0:
                begin(0, remaining: 2, continuation: 0xA0 ... 0xBF)
            case 0xE1 ... 0xEC, 0xEE ... 0xEF:
                begin(byte & 0x0F, remaining: 2)
            case 0xED:
                begin(0x0D, remaining: 2, continuation: 0x80 ... 0x9F)
            case 0xF0:
                begin(0, remaining: 3, continuation: 0x90 ... 0xBF)
            case 0xF1 ... 0xF3:
                begin(byte & 0x07, remaining: 3)
            case 0xF4:
                begin(0x04, remaining: 3, continuation: 0x80 ... 0x8F)
            default:
                scalars.append(.replacement)
            }
        }
        return scalars
    }

    private mutating func begin(
        _ bits: UInt8,
        remaining: Int,
        continuation: ClosedRange<UInt8> = 0x80 ... 0xBF
    ) {
        scalar = UInt32(bits)
        self.remaining = remaining
        self.continuation = continuation
    }
}

extension Unicode.Scalar {
    static let replacement: Unicode.Scalar = "\u{FFFD}"
}
