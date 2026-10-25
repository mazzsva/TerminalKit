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
        let values = [isRelease ? button | 3 : button, column + 1, row + 1].map { min($0 + 32, 255) }
        return Array("\u{1B}[M".utf8) + values.map(UInt8.init)
    }
}
