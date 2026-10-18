import AppKit

extension NSEvent {
    var wordMovementInput: [UInt8]? {
        guard modifierFlags.contains(.option), let key = charactersIgnoringModifiers?.unicodeScalars.first else {
            return nil
        }
        return switch NSEvent.SpecialKey(rawValue: Int(key.value)) {
        case .leftArrow: [0x1B, 0x62]
        case .rightArrow: [0x1B, 0x66]
        default: nil
        }
    }

    func metaInput(applicationCursorKeys: Bool) -> [UInt8]? {
        let characters = characters(byApplyingModifiers: modifierFlags.subtracting(.option))
        return terminalInput(characters: characters, applicationCursorKeys: applicationCursorKeys).map { [0x1B] + $0 }
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
                .terminalSequence(applicationCursorKeys: applicationCursorKeys)
        {
            return Array(sequence.utf8)
        }
        guard !characters.unicodeScalars.contains(where: { (0xF700 ... 0xF7FF).contains($0.value) }) else {
            return nil
        }
        return Array(characters.utf8)
    }
}

extension NSEvent.SpecialKey {
    fileprivate static var escape: Self {
        Self(rawValue: 0x1B)
    }

    fileprivate func terminalSequence(applicationCursorKeys: Bool) -> String? {
        let cursorKey = applicationCursorKeys ? "\u{1B}O" : "\u{1B}["
        return switch self {
        case .carriageReturn, .enter: "\r"
        case .tab: "\t"
        case .delete: "\u{7F}"
        case .escape: "\u{1B}"
        case .upArrow: cursorKey + "A"
        case .downArrow: cursorKey + "B"
        case .rightArrow: cursorKey + "C"
        case .leftArrow: cursorKey + "D"
        case .home: cursorKey + "H"
        case .end: cursorKey + "F"
        case .pageUp: "\u{1B}[5~"
        case .pageDown: "\u{1B}[6~"
        case .deleteForward: "\u{1B}[3~"
        case .backTab: "\u{1B}[Z"
        default: nil
        }
    }
}
