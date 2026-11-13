@testable import TerminalCore

extension Terminal {
    @discardableResult
    mutating func receive(_ text: String) -> String {
        String(decoding: receive(Array(text.utf8)), as: UTF8.self)
    }

    static func laidOut(_ lines: ArraySlice<Line>, columns: Int) -> [Line] {
        reflow(Array(lines), columns: columns, cursor: nil).lines.map(trimmed)
    }
}
