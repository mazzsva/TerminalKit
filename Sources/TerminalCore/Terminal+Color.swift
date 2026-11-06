import Foundation

extension Terminal {
    package struct DefaultColors: Equatable, Sendable {
        package var foreground: RGB
        package var background: RGB
        package var cursor: RGB
        package var selection: RGB
        package var bold: RGB
        package var ansi: [RGB]

        package init(foreground: RGB, background: RGB, cursor: RGB, selection: RGB, bold: RGB, ansi: [RGB]) {
            self.foreground = foreground
            self.background = background
            self.cursor = cursor
            self.selection = selection
            self.bold = bold
            self.ansi = ansi
        }
    }

    package struct ChangedColors: Equatable, Sendable {
        package var foreground: RGB?
        package var background: RGB?
        package var cursor: RGB?
        package var selection: RGB?
        package var bold: RGB?
        package var indexed: [UInt8: RGB] = [:]

        package init() {}

        package var isEmpty: Bool {
            self == ChangedColors()
        }
    }

    private enum ColorSlot {
        case indexed(UInt8)
        case foreground
        case background
        case cursor
        case selection
        case bold
        case trackingForeground
        case fixed(RGB)
    }

    private static let black = RGB(red: 0, green: 0, blue: 0)
    private static let white = RGB(red: 0xFFFF, green: 0xFFFF, blue: 0xFFFF)

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
            let index = Self.integer(fields[fields.startIndex])
            let item = fields[fields.startIndex + 1]
            fields = fields.dropFirst(2)
            guard (0 ... 260).contains(index),
                apply(item, to: Self.indexedSlot(index), command: "4;\(index)")
            else {
                return
            }
        }
    }

    mutating func changeSpecialColors(_ text: Substring) {
        var fields = Self.fields(of: text)[...]
        while fields.count >= 2 {
            let index = Self.integer(fields[fields.startIndex])
            let item = fields[fields.startIndex + 1]
            fields = fields.dropFirst(2)
            guard (0 ... 4).contains(index),
                apply(item, to: index == 0 ? .bold : .fixed(Self.black), command: "5;\(index)")
            else {
                return
            }
        }
    }

    mutating func changeDynamicColors(_ text: Substring, from first: Int) {
        for (number, item) in zip(first ... 19, Self.fields(of: text)) {
            guard apply(item, to: Self.dynamicSlot(number), command: "\(number)") else {
                return
            }
        }
    }

    mutating func resetIndexedColors(_ text: Substring?) {
        guard let text, !text.isEmpty else {
            changedColors.indexed = [:]
            return
        }
        for field in Self.fields(of: text) {
            let index = Self.integer(field)
            guard (0 ... 260).contains(index) else {
                return
            }
            if index < 256 {
                changedColors.indexed[UInt8(index)] = nil
            }
        }
    }

    mutating func resetSpecialColors(_ text: Substring) {
        for field in Self.fields(of: text) {
            let index = Self.integer(field)
            guard (0 ... 4).contains(index) else {
                return
            }
            if index == 0 {
                changedColors.bold = nil
            }
        }
    }

    mutating func resetDynamicColor(_ number: Int) {
        switch number {
        case 10:
            changedColors.foreground = nil
        case 11:
            changedColors.background = nil
        case 12:
            changedColors.cursor = nil
        default:
            changedColors.selection = nil
        }
    }

    private static func fields(of text: Substring) -> [Substring] {
        text.unicodeScalars.split(separator: ";", omittingEmptySubsequences: false).map(Substring.init)
    }

    private static func integer(_ field: Substring) -> Int {
        NSString(string: String(field)).integerValue
    }

    private static func indexedSlot(_ index: Int) -> ColorSlot {
        switch index {
        case ..<256:
            .indexed(UInt8(index))
        case 256:
            .bold
        default:
            .trackingForeground
        }
    }

    private static func dynamicSlot(_ number: Int) -> ColorSlot {
        switch number {
        case 10:
            .foreground
        case 11:
            .background
        case 12:
            .cursor
        case 14, 16:
            .fixed(white)
        case 17:
            .selection
        case 19:
            .trackingForeground
        default:
            .fixed(black)
        }
    }

    private mutating func apply(_ item: Substring, to slot: ColorSlot, command: String) -> Bool {
        if item == "?" {
            if let color = color(in: slot) {
                let rgb = String(format: "rgb:%04x/%04x/%04x", color.red, color.green, color.blue)
                replies += "\u{1B}]\(command);\(rgb)\u{7}".utf8
            }
            return true
        }
        guard let color = Self.color(specification: item) else {
            return false
        }
        switch slot {
        case .indexed(let index):
            changedColors.indexed[index] = color
        case .foreground:
            changedColors.foreground = color
        case .background:
            changedColors.background = color
        case .cursor:
            changedColors.cursor = color
        case .selection:
            changedColors.selection = color
        case .bold:
            changedColors.bold = color
        case .trackingForeground, .fixed:
            break
        }
        return true
    }

    private func color(in slot: ColorSlot) -> RGB? {
        switch slot {
        case .indexed(let index):
            if let color = changedColors.indexed[index] {
                return color
            }
            guard index >= 16 else {
                return defaultColors?.ansi[Int(index)]
            }
            let color = Self.standardColor(index)
            return RGB(
                red: UInt16(color.red) * 257,
                green: UInt16(color.green) * 257,
                blue: UInt16(color.blue) * 257
            )
        case .foreground, .trackingForeground:
            return changedColors.foreground ?? defaultColors?.foreground
        case .background:
            return changedColors.background ?? defaultColors?.background
        case .cursor:
            return changedColors.cursor ?? defaultColors?.cursor
        case .selection:
            return changedColors.selection ?? defaultColors?.selection
        case .bold:
            return changedColors.bold ?? defaultColors?.bold
        case .fixed(let color):
            return color
        }
    }

    private static func color(specification: Substring) -> RGB? {
        if specification.hasPrefix("#") {
            return hashColor(specification.dropFirst())
        }
        if specification.hasPrefix("rgb:") {
            return components(of: specification.dropFirst(4), scaledBy: scaledHexComponent)
        }
        if specification.hasPrefix("rgbi:") {
            return components(of: specification.dropFirst(5), scaledBy: intensityComponent)
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

    private static func intensityComponent(_ part: Substring) -> UInt16? {
        let value = NSString(string: String(part)).doubleValue
        return (0 ... 1).contains(value) ? UInt16((value * 65_535).rounded()) : nil
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
