import AppKit
import TerminalCore

extension NSColor {
    static func terminal(_ color: Terminal.Color, ansiColors: [NSColor]) -> NSColor? {
        switch color {
        case .default:
            nil
        case .indexed(let index) where index < 16:
            ansiColors[Int(index)]
        case .indexed(let index) where index < 232:
            NSColor(cubeColor(Int(index) - 16))
        case .indexed(let index):
            NSColor(gray: 8 + (index - 232) * 10)
        case .rgb(let red, let green, let blue):
            NSColor((red, green, blue))
        }
    }

    var terminalRGB: Terminal.RGB? {
        guard let color = usingColorSpace(.sRGB) else {
            return nil
        }
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
            .map { UInt16((min(1, max(0, $0)) * 65_535).rounded()) }
        return Terminal.RGB(red: components[0], green: components[1], blue: components[2])
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
