import AppKit

extension NSEvent {
    func metaInput(applicationCursorKeys: Bool) -> [UInt8]? {
        let modifierFlags = modifierFlags.subtracting(.option)
        guard
            let event = NSEvent.keyEvent(
                with: type,
                location: locationInWindow,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: windowNumber,
                context: nil,
                characters: characters(byApplyingModifiers: modifierFlags) ?? "",
                charactersIgnoringModifiers: charactersIgnoringModifiers ?? "",
                isARepeat: isARepeat,
                keyCode: keyCode
            ),
            let input = event.terminalInput(applicationCursorKeys: applicationCursorKeys)
        else {
            return nil
        }
        return [0x1B] + input
    }

    func terminalInput(applicationCursorKeys: Bool = false) -> [UInt8]? {
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
