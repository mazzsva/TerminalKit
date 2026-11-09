import AppKit

enum TerminalKeyInput: Equatable {
    case bytes([UInt8])
    case nothing
    case scroll
    case text
}

struct TerminalKeyModes {
    var usesOptionAsMetaKey = false
    var usesApplicationCursorKeys = false
    var usesApplicationKeypad = false
    var isAlternateScreenActive = false
}

extension NSEvent {
    func terminalKeyInput(_ modes: TerminalKeyModes) -> TerminalKeyInput {
        let flags = modifierFlags
        guard let key = charactersIgnoringModifiers?.unicodeScalars.first?.value else {
            return .text
        }
        let modifiers = Self.mappingModifiers(flags)
        if flags.contains(.command) {
            if let sequence = Self.keyMappings[key]?[modifiers],
                !(flags.contains(.shift)
                    && [UInt32(NSLeftArrowFunctionKey), UInt32(NSRightArrowFunctionKey)].contains(key))
            {
                return .bytes(Array(sequence.utf8))
            }
            return key == 0x0D ? returnInput(modes) : .nothing
        }
        if let sequence = Self.keyMappings[key]?[modifiers] {
            return .bytes(Array(sequence.utf8))
        }
        let shift = flags.contains(.shift)
        let control = flags.contains(.control)
        let meta = flags.contains(.option) && modes.usesOptionAsMetaKey
        let cursor = modes.usesApplicationCursorKeys ? "\u{1B}O" : "\u{1B}["
        switch key {
        case 0xF700 ... 0xF703:
            let sequence = cursor + ["A", "B", "D", "C"][Int(key - 0xF700)]
            return .bytes(Array(((meta ? "\u{1B}" : "") + sequence).utf8))
        case 0xF729, 0xF72B, 0xF72C, 0xF72D:
            guard shift != modes.isAlternateScreenActive else {
                return .scroll
            }
            if meta {
                return metaInput(of: key, shift: shift, control: control)
            }
            let sequence =
                switch key {
                case 0xF729: cursor + "H"
                case 0xF72B: cursor + "F"
                case 0xF72C: "\u{1B}[5~"
                default: "\u{1B}[6~"
                }
            return .bytes(Array(sequence.utf8))
        case 0xF700 ... 0xF8FF:
            return meta ? metaInput(of: key, shift: shift, control: control) : .nothing
        case 0x0D:
            return returnInput(modes)
        case 0x03:
            if meta {
                return .bytes([0x1B, 0x03])
            }
            return .bytes(modes.usesApplicationKeypad ? [0x1B, 0x4F, 0x4D] : [0x0D])
        case 0x09, 0x19:
            return .bytes((meta ? [0x1B] : []) + (shift ? [0x1B, 0x5B, 0x5A] : [0x09]))
        case 0x7F:
            return .bytes(meta ? [0x1B, shift || control ? 0x08 : 0x7F] : [0x7F])
        case 0x1B:
            return .bytes(meta ? [0x1B, 0x1B] : [0x1B])
        case 0x20:
            return meta ? .bytes([0x1B, 0x20]) : control ? .bytes([0x00]) : .text
        default:
            break
        }
        if flags.contains(.numericPad) {
            if meta {
                return .bytes([0x1B] + Array(charactersIgnoringModifiers?.utf8 ?? "".utf8))
            }
            if modes.usesApplicationKeypad, let final = Self.keypadFinals[key] {
                return .bytes([0x1B, 0x4F, final])
            }
            if modifiers == 0 {
                return .text
            }
            return modifiers == 2 ? .nothing : .bytes(Array((charactersIgnoringModifiers ?? "").utf8))
        }
        if meta {
            let text = control ? characters(byApplyingModifiers: .control) : charactersIgnoringModifiers
            return .bytes([0x1B] + Array((text ?? "").utf8))
        }
        guard control else {
            return .text
        }
        guard !flags.contains(.option) else {
            return .bytes(Array((characters ?? "").utf8))
        }
        let scalars = Array((characters ?? "").unicodeScalars)
        if shift, Character(UnicodeScalar(key) ?? " ").isLetter {
            return scalars == ["\r"] ? .bytes([0x1B, 0x0D]) : .nothing
        }
        guard scalars.count == 1, scalars[0].value < 0x20 || scalars[0].value == 0x7F else {
            return .nothing
        }
        return .bytes([UInt8(scalars[0].value)])
    }

    private func returnInput(_ modes: TerminalKeyModes) -> TerminalKeyInput {
        let flags = modifierFlags
        if flags.contains(.option) && modes.usesOptionAsMetaKey {
            return .bytes([0x1B, 0x0D])
        }
        if flags.contains(.control) && !flags.contains(.option) && !flags.contains(.command) {
            return .text
        }
        return .bytes(flags.contains(.shift) ? [0x1B, 0x0D] : [0x0D])
    }

    private func metaInput(of key: UInt32, shift: Bool, control: Bool) -> TerminalKeyInput {
        guard shift || control else {
            return .bytes([0x1B, UInt8(key & 0xFF)])
        }
        let text = characters(byApplyingModifiers: modifierFlags.intersection([.shift, .control])) ?? ""
        return .bytes([0x1B] + Array(text.utf8))
    }

    private static func mappingModifiers(_ flags: ModifierFlags) -> Int {
        (flags.contains(.shift) ? 1 : 0) | (flags.contains(.control) ? 2 : 0) | (flags.contains(.option) ? 4 : 0)
    }

    private static let keypadFinals: [UInt32: UInt8] = [
        0x30: 0x70, 0x31: 0x71, 0x32: 0x72, 0x33: 0x73, 0x34: 0x74, 0x35: 0x75, 0x36: 0x76, 0x37: 0x77, 0x38: 0x78,
        0x39: 0x79, 0x2E: 0x6E, 0x2B: 0x6C, 0x2D: 0x6D,
    ]

    private static let keyMappings: [UInt32: [Int: String]] = {
        var mappings: [UInt32: [Int: String]] = [:]
        let functionNumbers = [15, 17, 18, 19, 20, 21, 23, 24, 25, 26, 28, 29, 31, 32, 33, 34]
        for (index, final) in ["P", "Q", "R", "S"].enumerated() {
            mappings[UInt32(NSF1FunctionKey + index), default: [:]][0] = "\u{1B}O\(final)"
        }
        for (index, number) in functionNumbers.enumerated() {
            mappings[UInt32(NSF5FunctionKey + index), default: [:]][0] = "\u{1B}[\(number)~"
        }
        for index in 0 ..< 8 {
            mappings[UInt32(NSF5FunctionKey + index), default: [:]][1] = "\u{1B}[\(functionNumbers[index + 8])~"
        }
        for index in 0 ..< 15 {
            mappings[UInt32(NSF1FunctionKey + index), default: [:]][4] = "\u{1B}[\(functionNumbers[index + 1])~"
        }
        mappings[UInt32(NSLeftArrowFunctionKey)] = [1: "\u{1B}[1;2D", 2: "\u{1B}[1;5D", 4: "\u{1B}b"]
        mappings[UInt32(NSRightArrowFunctionKey)] = [1: "\u{1B}[1;2C", 2: "\u{1B}[1;5C", 4: "\u{1B}f"]
        mappings[UInt32(NSDeleteFunctionKey)] = [
            0: "\u{1B}[3~", 1: "\u{1B}[3;2~", 2: "\u{1B}[3;5~", 6: "\u{1B}\u{1B}[3;5~",
        ]
        return mappings
    }()

    func otherKeyInput(level: Int, usesOptionAsMetaKey: Bool) -> [UInt8]? {
        guard level > 0, modifierFlags.isDisjoint(with: [.command, .numericPad]),
            let key = charactersIgnoringModifiers?.unicodeScalars.first
        else {
            return nil
        }
        let usesMeta = usesOptionAsMetaKey && modifierFlags.contains(.option)
        let modifiers = terminalModifiers - (modifierFlags.contains(.option) && !usesMeta ? 3 : 1)
        let isControl = modifierFlags.contains(.control)
        let number: UInt32? =
            switch NSEvent.SpecialKey(rawValue: Int(key.value)) {
            case .carriageReturn, .tab: key.value
            case .backTab: level > 1 && modifiers & 6 != 0 ? 9 : nil
            case .delete: level > 1 && modifiers & 3 != 0 ? (isControl ? 8 : 127) : nil
            case .escape: level > 1 || usesMeta ? 27 : nil
            case _
            where key.value < 0x20 || (0xF700 ... 0xF8FF).contains(key.value)
                || isControl && key.value >= 0x7F && characters?.unicodeScalars.first?.value ?? 0 < 0x20:
                nil
            case _ where level > 1: modifiers & 6 != 0 ? key.value : nil
            default:
                isControl
                    && (key.value < 0x40
                        ? modifiers == 7 || !" 2345678/".unicodeScalars.contains(key) : key.value >= 0x7F)
                    ? key.value : nil
            }
        guard let number else {
            return nil
        }
        let parameter = (level > 1 ? modifiers : modifiers & (usesMeta && [9, 13].contains(number) ? 1 : 5)) + 1
        return parameter > 1 ? Array("\u{1B}[27;\(parameter);\(number)~".utf8) : nil
    }

    private var terminalModifiers: Int {
        [(NSEvent.ModifierFlags.shift, 1), (.option, 2), (.control, 4)]
            .reduce(1) { modifierFlags.contains($1.0) ? $0 + $1.1 : $0 }
    }
}

extension NSEvent.SpecialKey {
    fileprivate static var escape: Self {
        Self(rawValue: 0x1B)
    }
}
