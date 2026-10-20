import AppKit

extension NSEvent {
    var wordMovementInput: [UInt8]? {
        guard modifierFlags.intersection([.option, .command]) == .option,
            let key = charactersIgnoringModifiers?.unicodeScalars.first
        else {
            return nil
        }
        return switch NSEvent.SpecialKey(rawValue: Int(key.value)) {
        case .leftArrow: [0x1B, 0x62]
        case .rightArrow: [0x1B, 0x66]
        default: nil
        }
    }

    var lineDeletionInput: [UInt8]? {
        modifierFlags.intersection([.control, .option, .command]) == .command && charactersIgnoringModifiers == "\u{7F}"
            ? [0x15] : nil
    }

    var controlInput: [UInt8]? {
        guard modifierFlags.intersection([.control, .option, .command]) == .control,
            let characters = charactersIgnoringModifiers, characters.unicodeScalars.count == 1,
            let key = characters.unicodeScalars.first
        else {
            return nil
        }
        return switch key {
        case "2", "@", " ": [0x00]
        case "3": [0x1B]
        case "4": [0x1C]
        case "5": [0x1D]
        case "6", "^": [0x1E]
        case "7", "/", "-", "_": [0x1F]
        case "8", "?": [0x7F]
        case "a" ... "z", "A" ... "Z", "[", "\\", "]": [UInt8(key.value) & 0x1F]
        default: nil
        }
    }

    func metaInput(applicationCursorKeys: Bool) -> [UInt8]? {
        guard let key = charactersIgnoringModifiers?.unicodeScalars.first, !(0xF700 ... 0xF8FF).contains(key.value)
        else {
            return nil
        }
        let characters = characters(byApplyingModifiers: modifierFlags.subtracting(.option))
        return terminalInput(characters: characters, applicationCursorKeys: applicationCursorKeys).map { [0x1B] + $0 }
    }

    func disambiguatedInput(usesOptionAsMetaKey: Bool) -> [UInt8]? {
        guard let key = charactersIgnoringModifiers?.lowercased().unicodeScalars.first else {
            return nil
        }
        let modifiers = terminalModifiers
        let number: UInt32
        switch NSEvent.SpecialKey(rawValue: Int(key.value)) {
        case .carriageReturn, .enter: number = 13
        case .tab, .backTab: number = 9
        case .delete: number = 127
        case .escape: number = 27
        case let specialKey where (0xF700 ... 0xF8FF).contains(key.value):
            return specialKey.terminalSequence(applicationCursorKeys: false, modifiers: modifiers, disambiguates: true)
                .map { Array($0.utf8) }
        default:
            guard
                modifierFlags.contains(.control) || modifierFlags.contains(.command)
                    || usesOptionAsMetaKey && modifierFlags.contains(.option),
                let key = modifierFlags.contains(.shift)
                    ? characters(byApplyingModifiers: [])?.unicodeScalars.first : key,
                key.value >= 0x20, key.value < 0x7F || !modifierFlags.contains(.control)
            else {
                return nil
            }
            number = key.value
        }
        guard modifiers > 1 || number == 27 else {
            return nil
        }
        return Array("\u{1B}[\(number)\(modifiers > 1 ? ";\(modifiers)" : "")u".utf8)
    }

    func terminalInput(applicationCursorKeys: Bool = false) -> [UInt8]? {
        terminalInput(characters: characters, applicationCursorKeys: applicationCursorKeys)
    }

    private func terminalInput(characters: String?, applicationCursorKeys: Bool) -> [UInt8]? {
        guard !modifierFlags.contains(.command), let characters, !characters.isEmpty else {
            return nil
        }
        if let key = charactersIgnoringModifiers?.unicodeScalars.first,
            let sequence = NSEvent.SpecialKey(rawValue: Int(key.value))
                .terminalSequence(applicationCursorKeys: applicationCursorKeys, modifiers: terminalModifiers)
        {
            return Array(sequence.utf8)
        }
        guard !characters.unicodeScalars.contains(where: { (0xF700 ... 0xF7FF).contains($0.value) }) else {
            return nil
        }
        return Array(characters.utf8)
    }

    private var terminalModifiers: Int {
        [(NSEvent.ModifierFlags.shift, 1), (.option, 2), (.control, 4), (.command, 8)]
            .reduce(1) { modifierFlags.contains($1.0) ? $0 + $1.1 : $0 }
    }
}

extension NSEvent.SpecialKey {
    fileprivate static var escape: Self {
        Self(rawValue: 0x1B)
    }

    fileprivate func terminalSequence(applicationCursorKeys: Bool, modifiers: Int, disambiguates: Bool = false)
        -> String?
    {
        switch self {
        case .carriageReturn, .enter: "\r"
        case .tab: "\t"
        case .delete: "\u{7F}"
        case .escape: "\u{1B}"
        case .backTab: "\u{1B}[Z"
        default:
            if let final = cursorFinal, !disambiguates || self != .f3 {
                if modifiers > 1 {
                    "\u{1B}[1;\(modifiers)\(final)"
                } else {
                    (!disambiguates && (applicationCursorKeys || !"ABCD".contains(final)) ? "\u{1B}O" : "\u{1B}[")
                        + final
                }
            } else if let number = tildeNumber {
                modifiers > 1 ? "\u{1B}[\(number);\(modifiers)~" : "\u{1B}[\(number)~"
            } else {
                nil
            }
        }
    }

    private var cursorFinal: String? {
        switch self {
        case .upArrow: "A"
        case .downArrow: "B"
        case .rightArrow: "C"
        case .leftArrow: "D"
        case .home: "H"
        case .end: "F"
        case .f1: "P"
        case .f2: "Q"
        case .f3: "R"
        case .f4: "S"
        default: nil
        }
    }

    private var tildeNumber: Int? {
        switch self {
        case .deleteForward: 3
        case .pageUp: 5
        case .pageDown: 6
        case .f3: 13
        case .f5: 15
        case .f6: 17
        case .f7: 18
        case .f8: 19
        case .f9: 20
        case .f10: 21
        case .f11: 23
        case .f12: 24
        default: nil
        }
    }
}
