import AppKit

extension TerminalContentView {
    struct Selection: Equatable {
        struct Point: Comparable {
            var line: Int
            var column: Int

            static func < (lhs: Point, rhs: Point) -> Bool {
                (lhs.line, lhs.column) < (rhs.line, rhs.column)
            }
        }

        var anchor: Point
        var head: Point

        func columns(inLine line: Int, count: Int) -> Range<Int>? {
            let start = min(anchor, head)
            let end = max(anchor, head)
            guard start.line <= line, line <= end.line else {
                return nil
            }
            let lowerBound = line == start.line ? min(start.column, count) : 0
            let upperBound = line == end.line ? min(end.column, count) : count
            return lowerBound ..< max(upperBound, lowerBound)
        }
    }

    override func mouseDown(with event: NSEvent) {
        insertedText = ""
        isOpeningLink = openLink(at: event)
        guard !isOpeningLink else {
            return
        }
        if pressesButton(0, for: event) {
            reportMouse(event, button: 0)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        guard event.modifierFlags.contains(.shift), let selection else {
            selectionClickCount = event.clickCount
            selectionOrigin = selectionUnit(at: location)
            selection = selectionOrigin
            clickLocation = location
            return
        }
        clickLocation = nil
        let point = selectionPoint(at: location)
        let terminal = session.terminal
        let start = max(
            min(selection.anchor, selection.head), Selection.Point(line: terminal.removedScrollbackCount, column: 0))
        let end = max(selection.anchor, selection.head)
        let position: (Selection.Point) -> Int = { $0.line * (terminal.columns + 1) + $0.column }
        let anchor = 2 * position(point) > position(start) + position(end) ? start : end
        selectionOrigin = Selection(anchor: anchor, head: anchor)
        extendSelection(to: location)
        selectionOrigin = self.selection
    }

    override func mouseDragged(with event: NSEvent) {
        autoscrollTask?.cancel()
        autoscrollTask = nil
        guard !isOpeningLink else {
            return
        }
        if reportsPressedButton(0) {
            reportDrag(event, button: 32)
            return
        }
        autoscroll(with: event)
        let location = convert(event.locationInWindow, from: nil)
        extendSelection(to: location)
        if !visibleRect.contains(location) {
            autoscrollTask = Task { [weak self, autoscrollClock] in
                try? await autoscrollClock.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled, pressedMouseButtons() & 1 != 0 else {
                    return
                }
                mouseDragged(with: event)
            }
        }
    }

    func moveCursor(to location: CGPoint, from clickLocation: CGPoint) {
        let terminal = session.terminal
        let cell = { (location: CGPoint) in
            (
                row: Int((location.y - Self.topPadding) / self.cellSize.height) - terminal.scrollback.count,
                column: Int(floor((location.x - Self.padding) / self.cellSize.width))
            )
        }
        let target = cell(location)
        guard terminal.mouseTracking == .off, target == cell(clickLocation),
            terminal.screen.indices.contains(target.row),
            (0 ..< terminal.columns).contains(target.column)
        else {
            return
        }
        var row = terminal.cursor.row
        var column = min(terminal.cursor.column, terminal.columns - 1)
        var keys = ""
        let cursorKey = terminal.usesApplicationCursorKeys ? "\u{1B}O" : "\u{1B}["
        func press(_ final: String, _ count: Int) {
            keys += String(repeating: cursorKey + final, count: max(count, 0))
        }
        while row != target.row {
            let isUp = target.row < row
            let isBoundary = isUp ? row == 0 || !terminal.screen[row - 1].isWrapped : !terminal.screen[row].isWrapped
            if isBoundary {
                if target.column < column {
                    press("D", column - target.column)
                    column = target.column
                }
                press(isUp ? "A" : "B", 1)
                row += isUp ? -1 : 1
            } else if isUp {
                press("D", column + 1)
                row -= 1
                column = terminal.columns - 1
            } else {
                press("C", terminal.columns - column)
                row += 1
                column = 0
            }
        }
        press(target.column < column ? "D" : "C", abs(target.column - column))
        session.send(Array(keys.utf8))
    }

    private func extendSelection(to location: CGPoint) {
        guard let selectionOrigin, selection != nil else {
            return
        }
        let unit = selectionUnit(at: location)
        selection =
            unit.anchor < selectionOrigin.anchor
            ? Selection(anchor: max(selectionOrigin.anchor, selectionOrigin.head), head: unit.anchor)
            : Selection(anchor: min(selectionOrigin.anchor, selectionOrigin.head), head: unit.head)
    }

    private func selectionUnit(at location: CGPoint) -> Selection {
        if selectionClickCount == 2, let word = word(at: location) {
            return word
        }
        let point = selectionPoint(at: location)
        guard selectionClickCount >= 3 else {
            return Selection(anchor: point, head: point)
        }
        let terminal = session.terminal
        let rows = rows(ofLineAt: point.line - terminal.removedScrollbackCount, limit: .max, in: terminal)
        return Selection(
            anchor: Selection.Point(line: terminal.removedScrollbackCount + rows.lowerBound, column: 0),
            head: Selection.Point(line: terminal.removedScrollbackCount + rows.upperBound, column: terminal.columns)
        )
    }

    private func word(at location: CGPoint) -> Selection? {
        let terminal = session.terminal
        let row = selectionPoint(at: location).line - terminal.removedScrollbackCount
        let column = min(max(Int(floor((location.x - Self.padding) / cellSize.width)), 0), terminal.columns - 1)
        guard
            let (cells, index) = cells(
                atRow: row, column: visualOrder(ofRow: row)?.columns.firstIndex(of: column) ?? column, in: terminal),
            let end = cells.lastIndex(where: { !$0.cell.isSpace }), index <= end
        else {
            return nil
        }
        var text = ""
        var starts: [Int] = []
        var count = 0
        for cell in cells[...end] {
            let character = terminal.character(of: cell.cell)
            starts.append(count)
            count += character.utf16.count
            text.append(character)
        }
        let range = NSAttributedString(string: text).doubleClick(at: starts[index])
        let first = cells[starts.lastIndex { $0 <= range.lowerBound } ?? index]
        let last = cells[starts.lastIndex { $0 < range.upperBound } ?? index]
        return Selection(
            anchor: Selection.Point(line: terminal.removedScrollbackCount + first.row, column: first.column),
            head: Selection.Point(
                line: terminal.removedScrollbackCount + last.row, column: last.column + Int(last.cell.width))
        )
    }

    private func selectionPoint(at location: CGPoint) -> Selection.Point {
        let terminal = session.terminal
        let lineCount = terminal.scrollback.count + terminal.rows
        let row = min(max(Int((location.y - Self.topPadding) / cellSize.height), 0), lineCount - 1)
        let x = (location.x - Self.padding) / cellSize.width
        var column = min(max(Int(x.rounded()), 0), terminal.columns)
        let line = line(at: row, in: terminal)
        if let order = Self.visualOrder(of: line, graphemes: terminal.graphemes),
            let column = order.logicalColumn(at: x, in: line)
        {
            return Selection.Point(line: terminal.removedScrollbackCount + row, column: column)
        }
        if column < line.count, line[column].width == 0 {
            column += x < CGFloat(column) ? -1 : 1
        }
        return Selection.Point(line: terminal.removedScrollbackCount + row, column: column)
    }
}
