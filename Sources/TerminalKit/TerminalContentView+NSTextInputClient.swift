import AppKit

extension TerminalContentView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let characters = text(of: string)
        let input = hasMarkedText() || characters != keyDownEvent?.characters ? nil : keyDownEvent.flatMap(encodedInput)
        markedString = NSAttributedString()
        scrollToBottom()
        session.send(input ?? Array(characters.utf8))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedString = string as? NSAttributedString ?? NSAttributedString(string: text(of: string))
        markedSelection = selectedRange
    }

    func unmarkText() {
        if hasMarkedText() {
            insertText(markedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        markedString = NSAttributedString()
    }

    func selectedRange() -> NSRange {
        hasMarkedText() ? markedSelection : NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        hasMarkedText()
            ? NSRange(location: 0, length: markedText.utf16.count) : NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
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
}

private func text(of string: Any) -> String {
    (string as? NSAttributedString)?.string ?? string as? String ?? ""
}
