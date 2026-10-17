@testable import TerminalCore

extension Terminal {
    @discardableResult
    mutating func receive(_ text: String) -> String {
        String(decoding: receive(Array(text.utf8)), as: UTF8.self)
    }
}
