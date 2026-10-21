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
        selectionClickCount = event.clickCount
        selectionOrigin = selectionUnit(at: convert(event.locationInWindow, from: nil))
        selection = selectionOrigin
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isOpeningLink else {
            return
        }
        if reportsMouse(for: event) {
            if session.liveTerminal.mouseTracking != .clicks, mousePosition(of: event) != lastMousePosition {
                reportMouse(event, button: 32)
            }
            return
        }
        autoscroll(with: event)
        guard let selectionOrigin, selection != nil else {
            return
        }
        let unit = selectionUnit(at: convert(event.locationInWindow, from: nil))
        selection =
            unit.anchor < selectionOrigin.anchor
            ? Selection(anchor: selectionOrigin.head, head: unit.anchor)
            : Selection(anchor: selectionOrigin.anchor, head: max(unit.head, selectionOrigin.head))
    }

    private func selectionUnit(at location: CGPoint) -> Selection {
        if selectionClickCount == 2, let word = word(at: location) {
            return word
        }
        let point = selectionPoint(at: location)
        return Selection(anchor: point, head: point)
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
        let row = Int((location.y - Self.padding) / cellSize.height)
        let column = Int(((location.x - Self.padding) / cellSize.width).rounded())
        return Selection.Point(
            line: terminal.removedScrollbackCount + min(max(row, 0), lineCount - 1),
            column: min(max(column, 0), terminal.columns)
        )
    }
}
