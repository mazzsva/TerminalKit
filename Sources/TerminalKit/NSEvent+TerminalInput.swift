import AppKit

extension NSEvent {
    var terminalInput: [UInt8]? {
        guard !modifierFlags.contains(.command), let characters, !characters.isEmpty else {
            return nil
        }
        if let sequence = specialKey?.terminalSequence {
            return Array(sequence.utf8)
        }
        guard !characters.unicodeScalars.contains(where: { (0xF700 ... 0xF8FF).contains($0.value) }) else {
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
        default: nil
        }
    }
}
