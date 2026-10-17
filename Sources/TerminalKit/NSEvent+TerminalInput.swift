import AppKit

extension NSEvent {
    var terminalInput: [UInt8]? {
        guard !modifierFlags.contains(.command), let characters, !characters.isEmpty else {
            return nil
        }
        guard !characters.unicodeScalars.contains(where: { (0xF700 ... 0xF8FF).contains($0.value) }) else {
            return nil
        }
        return Array(characters.utf8)
    }
}
