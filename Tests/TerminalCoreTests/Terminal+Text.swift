@testable import TerminalCore

extension Terminal {
    mutating func receive(_ text: String) {
        receive(Array(text.utf8))
    }
}
