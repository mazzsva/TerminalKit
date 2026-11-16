import AppKit

extension TerminalContentView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let characters = text(of: string)
        let input: [UInt8]? =
            if let event = keyDownEvent, characters == event.characters, case .bytes(let bytes) = keyInput(event) {
                bytes
            } else {
                nil
            }
        let deletions = deletions(replacing: replacementRange)
        insertedText = hasMarkedText() ? "" : characters
        markedString = NSAttributedString()
        scrollToBottom()
        session.send(deletions + (input ?? Array(characters.utf8)))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedString = string as? NSAttributedString ?? NSAttributedString(string: text(of: string))
        markedSelection = selectedRange
        session.send(deletions(replacing: replacementRange))
        insertedText = ""
    }

    func unmarkText() {
        if hasMarkedText() {
            insertText(markedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    func selectedRange() -> NSRange {
        hasMarkedText() ? markedSelection : NSRange(location: insertedText.utf16.count, length: 0)
    }

    func markedRange() -> NSRange {
        NSRange(location: hasMarkedText() ? 0 : NSNotFound, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let substring = Range(range, in: insertedText) else {
            return nil
        }
        actualRange?.pointee = range
        return NSAttributedString(string: String(insertedText[substring]))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .markedClauseSegment]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(cursorRect, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    private func deletions(replacing range: NSRange) -> [UInt8] {
        guard let replaced = Range(range, in: insertedText), replaced.upperBound == insertedText.endIndex else {
            return []
        }
        return Array(repeating: 0x7F, count: insertedText[replaced].count)
    }
}

private func text(of string: Any) -> String {
    (string as? NSAttributedString)?.string ?? string as? String ?? ""
}
