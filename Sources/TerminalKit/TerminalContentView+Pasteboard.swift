import AppKit

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

    @objc func paste(_ sender: Any?) {
        _ = readSelection(from: .general)
    }

    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        guard let text = pasteboard.string(forType: .string) else {
            return false
        }
        scrollToBottom()
        let lines = text.replacing("\r\n", with: "\r").replacing("\n", with: "\r")
        guard session.terminal.usesBracketedPaste else {
            session.send(Array(lines.utf8))
            return true
        }
        session.send(Array("\u{1B}[200~\(lines.replacing("\u{1B}", with: ""))\u{1B}[201~".utf8))
        return true
    }

    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        sendType == .string && returnType == nil && selectedText != nil
            ? self : super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)):
            selectedText != nil
        case #selector(paste(_:)):
            NSPasteboard.general.availableType(from: [.string]) != nil
        default:
            true
        }
    }
}
