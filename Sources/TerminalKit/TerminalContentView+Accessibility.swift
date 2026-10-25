import AppKit
import TerminalCore

extension TerminalContentView {
    struct AccessibilityText {
        struct Row {
            let text: String
            let length: Int
            let isWrapped: Bool
        }

        let revision: Int
        let string: String
        let rows: [NSRange]
        let lines: [NSRange]
        let lineOfRow: [Int]
        private let widthChangeCount: Int
        private let firstLine: Int
        private let scrollback: [Row]

        init(
            _ terminal: Terminal,
            revision: Int,
            widthChangeCount: Int = 0,
            reusing previous: AccessibilityText? = nil
        ) {
            self.revision = revision
            self.widthChangeCount = widthChangeCount
            firstLine = terminal.removedScrollbackCount
            let reusable = previous?.widthChangeCount == widthChangeCount ? previous : nil
            let graphemes = terminal.graphemes
            scrollback = terminal.scrollback.indices.map { index in
                let line = terminal.scrollback[index]
                let continues =
                    line.isWrapped && (index != terminal.scrollback.count - 1 || !terminal.isAlternateScreenActive)
                if let reusable,
                    case let cached = terminal.removedScrollbackCount + index - reusable.firstLine,
                    reusable.scrollback.indices.contains(cached),
                    reusable.scrollback[cached].isWrapped == continues
                {
                    return reusable.scrollback[cached]
                }
                return Self.row(line, continues: continues, cursorColumn: nil, graphemes: graphemes)
            }
            let cursorRow = terminal.cursor.row
            let screen = terminal.screen.indices.map { row in
                let line = terminal.screen[row]
                return Self.row(
                    line,
                    continues: line.isWrapped && row < terminal.rows - 1,
                    cursorColumn: row == cursorRow ? terminal.cursor.column : nil,
                    graphemes: graphemes
                )
            }
            let allRows = scrollback + screen
            var string = ""
            var rows: [NSRange] = []
            var lines: [NSRange] = []
            var lineOfRow: [Int] = []
            var length = 0
            var lineStart = 0
            rows.reserveCapacity(allRows.count)
            lineOfRow.reserveCapacity(allRows.count)
            for (index, row) in allRows.enumerated() {
                string += row.text
                rows.append(NSRange(location: length, length: row.length))
                length += row.length
                lineOfRow.append(lines.count)
                if !row.isWrapped {
                    if index < allRows.count - 1 {
                        string += "\n"
                        length += 1
                    }
                    lines.append(NSRange(location: lineStart, length: length - lineStart))
                    lineStart = length
                }
            }
            self.string = string
            self.rows = rows
            self.lines = lines
            self.lineOfRow = lineOfRow
        }

        private static func row(
            _ line: Terminal.Line,
            continues: Bool,
            cursorColumn: Int?,
            graphemes: Terminal.Graphemes
        ) -> Row {
            var end = textEnd(of: line, continues: continues)
            if let cursorColumn {
                end = max(end, min(cursorColumn, line.count))
            }
            var text = ""
            var length = 0
            for cell in line[..<end] where isText(cell) {
                let character = graphemes.character(of: cell)
                text.append(character)
                length += character.utf16.count
            }
            return Row(text: text, length: length, isWrapped: continues)
        }

        var length: Int {
            rows.last?.upperBound ?? 0
        }

        func row(containing index: Int) -> Int {
            var low = 0
            var high = rows.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if rows[middle].location <= index {
                    low = middle
                } else {
                    high = middle - 1
                }
            }
            return low
        }

        static func isText(_ cell: Terminal.Cell) -> Bool {
            cell.width > 0 && cell != .padding
        }

        private static func textEnd(of line: Terminal.Line, continues: Bool) -> Int {
            guard !continues else {
                return line.count
            }
            return (line.lastIndex { !$0.isSpace }).map { $0 + 1 } ?? 0
        }
    }

    var accessibilityText: AccessibilityText {
        if let cachedAccessibilityText, cachedAccessibilityText.revision == session.revision {
            return cachedAccessibilityText
        }
        let text = AccessibilityText(
            session.terminal,
            revision: session.revision,
            widthChangeCount: session.widthChangeCount,
            reusing: cachedAccessibilityText
        )
        cachedAccessibilityText = text
        return text
    }

    func scheduleAccessibilityNotification() {
        guard !isAccessibilityNotificationScheduled else {
            return
        }
        isAccessibilityNotificationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self else {
                return
            }
            isAccessibilityNotificationScheduled = false
            postAccessibilityNotifications(self)
        }
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    override func accessibilityValue() -> Any? {
        accessibilityText.string
    }

    override func accessibilityNumberOfCharacters() -> Int {
        accessibilityText.length
    }

    override func accessibilityVisibleCharacterRange() -> NSRange {
        let text = accessibilityText
        let visibleRect = enclosingScrollView?.documentVisibleRect ?? bounds
        let firstRow = row(at: visibleRect.minY + Self.padding, in: text)
        let lastRow = row(at: visibleRect.maxY - Self.padding - 1, in: text)
        return NSRange(
            location: text.rows[firstRow].location, length: text.rows[lastRow].upperBound - text.rows[firstRow].location
        )
    }

    override func accessibilitySelectedText() -> String? {
        selectedText ?? ""
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        let text = accessibilityText
        let terminal = session.terminal
        guard let selection, selection.anchor != selection.head else {
            let cursor = index(
                row: terminal.scrollback.count + terminal.cursor.row, column: terminal.cursor.column, in: text)
            return NSRange(location: cursor, length: 0)
        }
        let start = min(selection.anchor, selection.head)
        let end = max(selection.anchor, selection.head)
        let lowerBound = index(row: start.line - terminal.removedScrollbackCount, column: start.column, in: text)
        let upperBound = index(row: end.line - terminal.removedScrollbackCount, column: end.column, in: text)
        return NSRange(location: lowerBound, length: max(upperBound - lowerBound, 0))
    }

    override func accessibilityInsertionPointLineNumber() -> Int {
        let text = accessibilityText
        return text.lineOfRow[session.terminal.scrollback.count + session.terminal.cursor.row]
    }

    override func accessibilityLine(for index: Int) -> Int {
        let text = accessibilityText
        return text.lineOfRow[text.row(containing: min(max(index, 0), text.length))]
    }

    override func accessibilityRange(forLine line: Int) -> NSRange {
        let text = accessibilityText
        return text.lines.indices.contains(line) ? text.lines[line] : NSRange(location: NSNotFound, length: 0)
    }

    override func accessibilityString(for range: NSRange) -> String? {
        let text = accessibilityText
        guard let range = clamped(range, in: text) else {
            return nil
        }
        return (text.string as NSString).substring(with: range)
    }

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        accessibilityString(for: range).map { NSAttributedString(string: $0) }
    }

    override func accessibilityRange(for index: Int) -> NSRange {
        let text = accessibilityText
        guard index >= 0, index < text.length else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let row = text.row(containing: index)
        guard index < text.rows[row].upperBound else {
            return NSRange(location: index, length: 1)
        }
        var location = text.rows[row].location
        let terminal = session.terminal
        let graphemes = terminal.graphemes
        for cell in line(at: row, in: terminal) where AccessibilityText.isText(cell) {
            let length = graphemes.character(of: cell).utf16.count
            if index < location + length {
                return NSRange(location: location, length: length)
            }
            location += length
        }
        return NSRange(location: index, length: 1)
    }

    override func accessibilityRange(for point: NSPoint) -> NSRange {
        guard let window else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let text = accessibilityText
        let location = convert(window.convertPoint(fromScreen: point), from: nil)
        let row = row(at: location.y, in: text)
        var column = Int(max(location.x - Self.padding, 0) / cellSize.width)
        let line = line(at: row)
        if column < line.count, line[column].width == 0 {
            column -= 1
        }
        return accessibilityRange(for: min(index(row: row, column: column, in: text), max(text.length - 1, 0)))
    }

    override func accessibilityFrame(for range: NSRange) -> NSRect {
        let text = accessibilityText
        guard let window, let range = clamped(range, in: text) else {
            return .zero
        }
        let start = position(of: range.location, in: text)
        let end = range.length > 0 ? position(of: range.upperBound - 1, in: text) : start
        let endLine = line(at: end.row)
        let endColumn = end.column + (endLine.indices.contains(end.column) ? max(Int(endLine[end.column].width), 1) : 1)
        let frame =
            start.row == end.row
            ? rect(row: start.row, columns: start.column ..< endColumn)
            : rect(row: start.row, columns: start.column ..< session.terminal.columns)
                .union(rect(row: end.row, columns: 0 ..< endColumn))
        return window.convertToScreen(convert(frame, to: nil))
    }

    private func row(at y: CGFloat, in text: AccessibilityText) -> Int {
        min(max(Int((y - Self.padding) / cellSize.height), 0), text.rows.count - 1)
    }

    func index(row: Int, column: Int, in text: AccessibilityText) -> Int {
        guard row >= 0 else {
            return 0
        }
        guard row < text.rows.count else {
            return text.length
        }
        var index = text.rows[row].location
        let terminal = session.terminal
        let graphemes = terminal.graphemes
        for cell in line(at: row, in: terminal).prefix(max(column, 0)) where AccessibilityText.isText(cell) {
            index += graphemes.character(of: cell).utf16.count
        }
        return min(index, text.rows[row].upperBound)
    }

    func position(of index: Int, in text: AccessibilityText) -> (row: Int, column: Int) {
        let row = text.row(containing: index)
        var location = text.rows[row].location
        let terminal = session.terminal
        let graphemes = terminal.graphemes
        let line = line(at: row, in: terminal)
        for column in line.indices where AccessibilityText.isText(line[column]) {
            location += graphemes.character(of: line[column]).utf16.count
            if index < location {
                return (row, column)
            }
        }
        return (row, max(line.count - 1, 0))
    }

    private func clamped(_ range: NSRange, in text: AccessibilityText) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0, range.location <= text.length else {
            return nil
        }
        return NSRange(location: range.location, length: min(range.length, text.length - range.location))
    }
}
