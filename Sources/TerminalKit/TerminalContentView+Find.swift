import AppKit

extension TerminalContentView: NSTextFinderClient {
    var textFinder: NSTextFinder? {
        (enclosingScrollView as? TerminalScrollView)?.textFinder
    }

    var string: String {
        accessibilityText.string
    }

    var isSelectable: Bool {
        true
    }

    var firstSelectedRange: NSRange {
        accessibilitySelectedTextRange()
    }

    var selectedRanges: [NSValue] {
        get {
            [NSValue(range: accessibilitySelectedTextRange())]
        }
        set {
            guard let range = newValue.first?.rangeValue else {
                return
            }
            select(range)
        }
    }

    var visibleCharacterRanges: [NSValue] {
        [NSValue(range: accessibilityVisibleCharacterRange())]
    }

    override func performTextFinderAction(_ sender: Any?) {
        (enclosingScrollView as? TerminalScrollView)?.performTextFinderAction(sender)
    }

    func scrollRangeToVisible(_ range: NSRange) {
        guard let rect = characterRects(for: range).first else {
            return
        }
        scrollToVisible(rect.insetBy(dx: 0, dy: -cellSize.height))
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        characterRects(for: range).map(NSValue.init(rect:))
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: accessibilityText.length)
        return self
    }

    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let (start, end) = cellPositions(of: range) else {
            return
        }
        let graphemes = session.terminal.graphemes
        for row in start.row ... end.row {
            let line = line(at: row)
            let lowerBound = row == start.row ? start.column : 0
            let upperBound = row == end.row ? end.column : line.count
            for (columns, style) in Self.runs(in: line) {
                let clipped = max(columns.lowerBound, lowerBound) ..< min(columns.upperBound, upperBound)
                if !clipped.isEmpty {
                    drawText(line, columns: clipped, row: row, style: style, foreground: .black, graphemes: graphemes)
                }
            }
        }
    }

    func characterRects(for range: NSRange) -> [CGRect] {
        guard let (start, end) = cellPositions(of: range) else {
            return []
        }
        return (start.row ... end.row)
            .map { row in
                let lowerBound = row == start.row ? start.column : 0
                let upperBound = row == end.row ? end.column : max(line(at: row).count, lowerBound + 1)
                return rect(row: row, columns: lowerBound ..< max(upperBound, lowerBound + 1))
            }
    }

    private func select(_ range: NSRange) {
        guard range.length > 0, let (start, end) = cellPositions(of: range) else {
            selection = nil
            return
        }
        let firstLine = session.terminal.removedScrollbackCount
        selection = Selection(
            anchor: Selection.Point(line: firstLine + start.row, column: start.column),
            head: Selection.Point(line: firstLine + end.row, column: end.column)
        )
    }

    private func cellPositions(of range: NSRange) -> (start: (row: Int, column: Int), end: (row: Int, column: Int))? {
        let text = accessibilityText
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0, range.upperBound <= text.length
        else {
            return nil
        }
        let start = position(of: range.location, in: text)
        let last = range.length > 0 ? position(of: range.upperBound - 1, in: text) : start
        let line = line(at: last.row)
        let width = line.indices.contains(last.column) ? max(Int(line[last.column].width), 1) : 1
        return (start, (last.row, last.column + width))
    }
}
