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
        isOpeningLink = openLink(at: event)
        guard !isOpeningLink else {
            return
        }
        if reportsMouse(for: event) {
            reportMouse(event, button: 0)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        guard event.modifierFlags.contains(.shift), session.liveTerminal.mouseTracking == .off, let selection else {
            selectionClickCount = event.clickCount
            selectionOrigin = selectionUnit(at: location)
            selection = selectionOrigin
            return
        }
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
        guard !isOpeningLink else {
            return
        }
        if reportsMouse(for: event) {
            reportDrag(event, button: 32)
            return
        }
        autoscroll(with: event)
        extendSelection(to: convert(event.locationInWindow, from: nil))
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
        guard
            let (cells, index) = cells(
                atRow: selectionPoint(at: location).line - terminal.removedScrollbackCount,
                column: min(max(Int(floor((location.x - Self.padding) / cellSize.width)), 0), terminal.columns - 1),
                in: terminal
            ),
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
        let row = min(max(Int((location.y - Self.padding) / cellSize.height), 0), lineCount - 1)
        let x = (location.x - Self.padding) / cellSize.width
        var column = min(max(Int(x.rounded()), 0), terminal.columns)
        let line = line(at: row, in: terminal)
        if column < line.count, line[column].width == 0 {
            column += x < CGFloat(column) ? -1 : 1
        }
        return Selection.Point(line: terminal.removedScrollbackCount + row, column: column)
    }
}
