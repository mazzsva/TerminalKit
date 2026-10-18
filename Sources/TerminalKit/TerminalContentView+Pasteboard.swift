import AppKit

extension TerminalContentView: NSMenuItemValidation {
    var selectedText: String? {
        guard let selection, selection.anchor != selection.head else {
            return nil
        }
        let terminal = session.terminal
        let graphemes = terminal.graphemes
        let firstRow = max(min(selection.anchor, selection.head).line - terminal.removedScrollbackCount, 0)
        let lastRow = min(
            max(selection.anchor, selection.head).line - terminal.removedScrollbackCount,
            terminal.scrollback.count + terminal.rows - 1
        )
        let pieces = (firstRow ..< max(lastRow + 1, firstRow))
            .compactMap { row -> (text: String, continues: Bool)? in
                let line = line(at: row, in: terminal)
                guard let columns = selection.columns(inLine: terminal.removedScrollbackCount + row, count: line.count)
                else {
                    return nil
                }
                let continues = line.isWrapped && row < lastRow
                let end =
                    continues
                    ? columns.upperBound
                    : line[columns].lastIndex { !$0.isSpace }.map { $0 + 1 } ?? columns.lowerBound
                let cells = line[columns.lowerBound ..< end].filter { $0.width > 0 && $0 != .padding }
                return (String(cells.map(graphemes.character(of:))), continues)
            }
        guard !pieces.isEmpty else {
            return nil
        }
        return pieces.enumerated()
            .map { index, piece in piece.continues || index == pieces.count - 1 ? piece.text : piece.text + "\n" }
            .joined()
    }

    @objc func copy(_ sender: Any?) {
        copySelection(to: .general)
    }

    func copySelection(to pasteboard: NSPasteboard) {
        guard let selectedText else {
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(selectedText, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        paste(from: .general)
    }

    func paste(from pasteboard: NSPasteboard) {
        guard let text = pasteboard.string(forType: .string) else {
            return
        }
        paste(text: text)
    }

    func paste(text: String) {
        scrollToBottom()
        session.paste(text)
    }

    @objc override func selectAll(_ sender: Any?) {
        let terminal = session.terminal
        let lastRow = (terminal.scrollback + terminal.screen).lastIndex { !$0.allSatisfy(\.isBlank) } ?? 0
        selection = Selection(
            anchor: Selection.Point(line: terminal.removedScrollbackCount, column: 0),
            head: Selection.Point(line: terminal.removedScrollbackCount + lastRow, column: terminal.columns)
        )
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [
            ("Copy", #selector(copy(_:))), ("Paste", #selector(paste(_:))), ("Select All", #selector(selectAll(_:))),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)):
            selectedText != nil
        case #selector(paste(_:)):
            NSPasteboard.general.availableType(from: [.string]) != nil
        case #selector(performTextFinderAction(_:)):
            (enclosingScrollView as? TerminalScrollView)?.validateMenuItem(menuItem) ?? false
        default:
            true
        }
    }
}
