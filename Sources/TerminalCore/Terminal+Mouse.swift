extension Terminal {
    package enum MouseTracking: Sendable {
        case off
        case clicks
        case drags
        case anyMotion
    }

    package func mouseReport(button: Int, column: Int, row: Int, isRelease: Bool) -> [UInt8] {
        if usesSGRMouseEncoding {
            return Array("\u{1B}[<\(button);\(column + 1);\(row + 1)\(isRelease ? "m" : "M")".utf8)
        }
        let button = isRelease ? button | 3 : button
        if usesURXVTMouseEncoding {
            return Array("\u{1B}[\(button + 32);\(column + 1);\(row + 1)M".utf8)
        }
        let values = [button, column + 1, row + 1].map { $0 + 32 }
        guard usesUTF8MouseEncoding else {
            return Array("\u{1B}[M".utf8) + values.map { UInt8(min($0, 255)) }
        }
        return Array("\u{1B}[M".utf8)
            + values.flatMap { UnicodeScalar(UInt32(min($0, 2047))).map { Array(String($0).utf8) } ?? [] }
    }
}
