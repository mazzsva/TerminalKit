import AppKit
import TerminalCore

extension TerminalContentView: NSMenuItemValidation, NSServicesMenuRequestor, NSTextInputTraits {
    var selectedText: String? {
        guard let selection, selection.anchor != selection.head else {
            return nil
        }
        let terminal = session.terminal
        let graphemes = terminal.graphemes
        let rows = selectedRows(of: selection, in: terminal)
        let lastRow = rows.upperBound - 1
        let pieces =
            rows
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
                let cells = line[columns.lowerBound ..< end].filter(\.isText)
                return (cells.map(graphemes.character(of:)).joined(), continues)
            }
        guard !pieces.isEmpty else {
            return nil
        }
        return pieces.enumerated()
            .map { index, piece in piece.continues || index == pieces.count - 1 ? piece.text : piece.text + "\n" }
            .joined()
    }

    var hasSelectedText: Bool {
        guard let selection, selection.anchor != selection.head else {
            return false
        }
        let terminal = session.terminal
        return selectedRows(of: selection, in: terminal)
            .contains { row in
                selection.columns(
                    inLine: terminal.removedScrollbackCount + row, count: line(at: row, in: terminal).count)
                    != nil
            }
    }

    private func selectedRows(of selection: Selection, in terminal: Terminal) -> Range<Int> {
        let firstRow = max(min(selection.anchor, selection.head).line - terminal.removedScrollbackCount, 0)
        let lastRow = min(
            max(selection.anchor, selection.head).line - terminal.removedScrollbackCount,
            terminal.scrollback.count + terminal.rows - 1
        )
        return firstRow ..< max(lastRow + 1, firstRow)
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

    var writingToolsBehavior: NSWritingToolsBehavior {
        get { .none }
        set {}
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        sendType == .string && returnType == nil && hasSelectedText
            ? self : super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let selectedText else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.setString(selectedText, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        paste(from: .general)
    }

    func paste(from pasteboard: NSPasteboard) {
        guard let text = Self.droppedText(from: pasteboard) else {
            return
        }
        paste(text: text)
    }

    func canPaste(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.fileURL, .string]) != nil
    }

    func paste(text: String) {
        insertedText = ""
        var text = text
        if session.liveTerminal.usesBracketedPaste {
            guard !TerminalSession.containsPasteEnd(text) else {
                let alert = NSAlert()
                alert.messageText =
                    "You cannot send the text to the terminal, because it contains invalid content for Bracketed Paste Mode."
                alert.informativeText =
                    "Bracketed Paste Mode is enabled in the terminal and the text to send contains the escape sequence that marks the end of pasted text. This is invalid for Bracketed Paste Mode, and could allow subsequent content in the text to perform arbitrary commands."
                alert.addButton(withTitle: "OK")
                _ = presentsAlert(alert, window)
                return
            }
        } else if text.unicodeScalars.contains(where: Self.isPastedControlCharacter) {
            let alert = NSAlert()
            alert.messageText = "Paste control characters?"
            alert.informativeText =
                "The text contains control characters, which could allow the pasted content to perform arbitrary commands.\n\nTo confirm and Paste, you can use ⇧⌘⏎."
            let paste = alert.addButton(withTitle: "Paste")
            paste.keyEquivalent = "\r"
            paste.keyEquivalentModifierMask = [.shift, .command]
            alert.addButton(withTitle: "Paste without Control Characters").keyEquivalent = ""
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1B}"
            switch presentsAlert(alert, nil) {
            case .alertFirstButtonReturn:
                break
            case .alertSecondButtonReturn:
                text.unicodeScalars.removeAll(where: Self.isPastedControlCharacter)
            default:
                return
            }
        }
        scrollToBottom()
        session.paste(text)
    }

    static func isPastedControlCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09 ... 0x0D, 0x85: false
        case 0x00 ... 0x1F, 0x7F ... 0x9F: true
        default: false
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        let terminal = session.terminal
        let isWritten = { (line: Terminal.Line) in !line.allSatisfy(\.isBlank) }
        let lastRow =
            terminal.screen.lastIndex(where: isWritten).map { terminal.scrollback.count + $0 }
            ?? terminal.scrollback.lastIndex(where: isWritten) ?? 0
        selectionClickCount = 1
        selection = Selection(
            anchor: Selection.Point(line: terminal.removedScrollbackCount, column: 0),
            head: Selection.Point(line: terminal.removedScrollbackCount + lastRow, column: terminal.columns)
        )
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if event.type == .leftMouseDown, window?.isKeyWindow != false, reportsMouse(for: event) {
            reportMouse(event, button: 0)
            return nil
        }
        let menu = NSMenu()
        menu.items = [#selector(copy(_:)), #selector(paste(_:))]
            .compactMap { action in
                let item = NSTextView.defaultMenu?.items.first { $0.action == action }?.copy() as? NSMenuItem
                item?.target = self
                return item
            }
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)):
            hasSelectedText
        case #selector(paste(_:)):
            canPaste(from: .general)
        case #selector(performTextFinderAction(_:)):
            (enclosingScrollView as? TerminalScrollView)?.validateMenuItem(menuItem) ?? false
        default:
            true
        }
    }
}
