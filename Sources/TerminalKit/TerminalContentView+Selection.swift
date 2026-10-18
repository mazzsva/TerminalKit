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
        if reportsMouse(for: event) {
            reportMouse(event, button: 0)
            return
        }
        let point = selectionPoint(at: convert(event.locationInWindow, from: nil))
        selection = Selection(anchor: point, head: point)
    }

    override func mouseDragged(with event: NSEvent) {
        if reportsMouse(for: event) {
            if session.liveTerminal.mouseTracking == .drags, mousePosition(of: event) != lastMousePosition {
                reportMouse(event, button: 32)
            }
            return
        }
        autoscroll(with: event)
        selection?.head = selectionPoint(at: convert(event.locationInWindow, from: nil))
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
