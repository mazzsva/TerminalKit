import AppKit
import TerminalCore

extension NSColor {
    private static let standardColors: [(red: UInt8, green: UInt8, blue: UInt8)] = [
        (0, 0, 0), (194, 54, 33), (37, 188, 36), (173, 173, 39),
        (73, 46, 225), (211, 56, 211), (51, 187, 200), (203, 204, 205),
        (129, 131, 131), (252, 57, 31), (49, 231, 34), (234, 236, 35),
        (88, 51, 255), (249, 53, 248), (20, 240, 240), (233, 235, 235),
    ]

    static func terminal(_ color: Terminal.Color) -> NSColor? {
        switch color {
        case .default:
            nil
        case .indexed(let index) where index < 16:
            NSColor(standardColors[Int(index)])
        case .indexed(let index) where index < 232:
            NSColor(cubeColor(Int(index) - 16))
        case .indexed(let index):
            NSColor(gray: 8 + (index - 232) * 10)
        case .rgb(let red, let green, let blue):
            NSColor((red, green, blue))
        }
    }

    private static func cubeColor(_ index: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
        return (levels[index / 36], levels[index / 6 % 6], levels[index % 6])
    }

    private convenience init(_ color: (red: UInt8, green: UInt8, blue: UInt8)) {
        self.init(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
    }

    private convenience init(gray: UInt8) {
        self.init((gray, gray, gray))
    }
}
