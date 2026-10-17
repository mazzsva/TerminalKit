import AppKit

extension NSEvent {
    var terminalInput: [UInt8]? {
        guard !modifierFlags.contains(.command), let characters, !characters.isEmpty else {
            return nil
        }
        if let key = charactersIgnoringModifiers?.unicodeScalars.first,
            let sequence = NSEvent.SpecialKey(rawValue: Int(key.value)).terminalSequence
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
    fileprivate var terminalSequence: String? {
        switch self {
        case .upArrow: "\u{1B}[A"
        case .downArrow: "\u{1B}[B"
        case .rightArrow: "\u{1B}[C"
        case .leftArrow: "\u{1B}[D"
        case .home: "\u{1B}[H"
        case .end: "\u{1B}[F"
        case .pageUp: "\u{1B}[5~"
        case .pageDown: "\u{1B}[6~"
        case .deleteForward: "\u{1B}[3~"
        case .enter: "\r"
        case .backTab: "\u{1B}[Z"
        default: nil
        }
    }
}
