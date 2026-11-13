import Foundation

extension Terminal {
    package struct DefaultColors: Equatable, Sendable {
        package var foreground: RGB
        package var background: RGB
        package var cursor: RGB

        package init(foreground: RGB, background: RGB, cursor: RGB) {
            self.foreground = foreground
            self.background = background
            self.cursor = cursor
        }

        package var isDark: Bool {
            func linear(_ value: UInt16) -> Double {
                let level = Double(value) / 65535
                return level <= 0.04045 ? level / 12.92 : pow((level + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(background.red) + 0.7152 * linear(background.green)
                + 0.0722 * linear(background.blue) < 0.179
        }
    }

    package struct ChangedColors: Equatable, Sendable {
        package var cursor: RGB?
        package var indexed: [UInt8: RGB] = [:]

        package init() {}

        package var isEmpty: Bool {
            self == ChangedColors()
        }
    }

    package static func standardColor(_ index: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
        guard index < 232 else {
            let gray = 8 + (index - 232) * 10
            return (gray, gray, gray)
        }
        let levels: [UInt8] = [0, 95, 135, 175, 215, 255]
        let cube = Int(index) - 16
        return (levels[cube / 36], levels[cube / 6 % 6], levels[cube % 6])
    }

    mutating func changeIndexedColors(_ text: Substring) {
        var fields = Self.fields(of: text)[...]
        while fields.count >= 2 {
            let index = NSString(string: String(fields[fields.startIndex])).integerValue
            let color = Self.color(specification: fields[fields.startIndex + 1])
            fields = fields.dropFirst(2)
            guard (0 ... 255).contains(index), let color else {
                return
            }
            changedColors.indexed[UInt8(index)] = color
        }
    }

    mutating func changeDynamicColors(_ text: Substring, from first: Int) {
        for (number, item) in zip(first ... 12, Self.fields(of: text)) {
            if item == "?" {
                if let color = dynamicColor(number) {
                    let rgb = String(format: "rgb:%04x/%04x/%04x", color.red, color.green, color.blue)
                    replies += "\u{1B}]\(number);\(rgb)\u{7}".utf8
                }
            } else if number == 12, let color = Self.color(specification: item) {
                changedColors.cursor = color
            } else {
                return
            }
        }
    }

    private func dynamicColor(_ number: Int) -> RGB? {
        switch number {
        case 10:
            defaultColors?.foreground
        case 11:
            defaultColors?.background
        default:
            changedColors.cursor ?? defaultColors?.cursor
        }
    }

    private static func fields(of text: Substring) -> [Substring] {
        text.unicodeScalars.split(separator: ";", omittingEmptySubsequences: false).map(Substring.init)
    }

    private static func color(specification: Substring) -> RGB? {
        if specification.hasPrefix("#") {
            return hashColor(specification.dropFirst())
        }
        if specification.hasPrefix("rgb:") {
            return components(of: specification.dropFirst(4), scaledBy: scaledHexComponent)
        }
        return nil
    }

    private static func hashColor(_ digits: Substring) -> RGB? {
        let digits = Array(digits.utf8)
        guard [3, 6, 9, 12].contains(digits.count) else {
            return nil
        }
        let width = digits.count / 3
        let parts = stride(from: 0, to: digits.count, by: width)
            .map { start in
                hexValue(digits[start ..< start + width]).map { UInt16($0 << (16 - 4 * width)) }
            }
        guard let red = parts[0], let green = parts[1], let blue = parts[2] else {
            return nil
        }
        return RGB(red: red, green: green, blue: blue)
    }

    private static func components(of text: Substring, scaledBy scale: (Substring) -> UInt16?) -> RGB? {
        let parts = text.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map(Substring.init)
        guard parts.count == 3,
            let red = scale(parts[0]),
            let green = scale(parts[1]),
            let blue = scale(parts[2])
        else {
            return nil
        }
        return RGB(red: red, green: green, blue: blue)
    }

    private static func scaledHexComponent(_ part: Substring) -> UInt16? {
        let bytes = Array(part.utf8)
        guard (1 ... 4).contains(bytes.count), let first = bytes.firstIndex(where: { $0 != 0x20 }),
            let value = hexValue(bytes[first...])
        else {
            return nil
        }
        let maximum = UInt32(1) << (4 * bytes.count) - 1
        return UInt16((value * 65_535 + maximum / 2) / maximum)
    }

    private static func hexValue(_ digits: ArraySlice<UInt8>) -> UInt32? {
        var value: UInt32 = 0
        for digit in digits {
            switch digit {
            case 0x30 ... 0x39:
                value = value * 16 + UInt32(digit - 0x30)
            case 0x41 ... 0x46:
                value = value * 16 + UInt32(digit - 0x37)
            case 0x61 ... 0x66:
                value = value * 16 + UInt32(digit - 0x57)
            default:
                return nil
            }
        }
        return value
    }
}
