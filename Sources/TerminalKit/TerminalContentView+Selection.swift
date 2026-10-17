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
        let point = selectionPoint(at: convert(event.locationInWindow, from: nil))
        selection = Selection(anchor: point, head: point)
    }

    override func mouseDragged(with event: NSEvent) {
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

extension TerminalContentView: NSServicesMenuRequestor, NSMenuItemValidation {
    var selectedText: String? {
        guard let selection, selection.anchor != selection.head else {
            return nil
        }
        let terminal = session.terminal
        let firstRow = max(min(selection.anchor, selection.head).line - terminal.removedScrollbackCount, 0)
        let lastRow = min(
            max(selection.anchor, selection.head).line - terminal.removedScrollbackCount,
            terminal.scrollback.count + terminal.rows - 1
        )
        let lines = (firstRow ..< max(lastRow + 1, firstRow))
            .compactMap { row -> String? in
                let line = line(at: row)
                guard let columns = selection.columns(inLine: terminal.removedScrollbackCount + row, count: line.count)
                else {
                    return nil
                }
                let end = line[columns].lastIndex { $0.character != " " }.map { $0 + 1 } ?? columns.lowerBound
                return String(line[columns.lowerBound ..< end].map(\.character))
            }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    @objc func copy(_ sender: Any?) {
        _ = writeSelection(to: .general, types: [.string])
    }

    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string), let selectedText else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.setString(selectedText, forType: .string)
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        sendType == .string && returnType == nil && selectedText != nil
            ? self : super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(copy(_:)) ? selectedText != nil : true
    }
}
