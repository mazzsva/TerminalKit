import AppKit

extension TerminalContentView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let characters = text(of: string)
        let input = hasMarkedText() || characters != keyDownEvent?.characters ? nil : keyDownEvent.flatMap(encodedInput)
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
        markedString = NSAttributedString()
    }

    func selectedRange() -> NSRange {
        hasMarkedText() ? markedSelection : NSRange(location: insertedText.utf16.count, length: 0)
    }

    func markedRange() -> NSRange {
        hasMarkedText()
            ? NSRange(location: 0, length: markedText.utf16.count) : NSRange(location: NSNotFound, length: 0)
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
        let replaced = Range(range, in: insertedText).map { insertedText[$0] }
        let count = replaced?.endIndex == insertedText.endIndex ? replaced?.count ?? 0 : 0
        return Array(repeating: 0x7F, count: count)
    }
}

private func text(of string: Any) -> String {
    (string as? NSAttributedString)?.string ?? string as? String ?? ""
}
