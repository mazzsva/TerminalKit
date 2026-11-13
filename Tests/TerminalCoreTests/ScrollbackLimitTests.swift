import Foundation
import Testing

@testable import TerminalCore

struct ScrollbackLimitTests {
    @Test func removesTheOldestSavedLinesAtTheLimit() {
        var terminal = Terminal(columns: 8, rows: 1)
        for start in stride(from: 1, through: 200_001, by: 1_000) {
            terminal.receive((start ..< start + 1_000).map { "\($0)\r\n" }.joined())
        }
        #expect(terminal.scrollback.count == Terminal.Scrollback.maximumCount)
        #expect(terminal.removedScrollbackCount == 101_000)
        #expect(text(of: terminal.scrollback[0], in: terminal) == "101001")
        #expect(text(of: terminal.scrollback[99_999], in: terminal) == "201000")
        #expect(terminal.scrollback.map { text(of: $0, in: terminal) } == (101_001 ... 201_000).map(String.init))
    }

    @Test func keepsTheLimitAfterOneLineMore() {
        var terminal = Terminal(columns: 8, rows: 1)
        terminal.receive((1 ... Terminal.Scrollback.maximumCount + 1).map { "\($0)\r\n" }.joined())
        #expect(terminal.scrollback.count == Terminal.Scrollback.maximumCount)
        #expect(terminal.removedScrollbackCount == 1)
        #expect(text(of: terminal.scrollback[0], in: terminal) == "2")
    }

    @Test func keepsTheLimitAfterAResize() throws {
        var terminal = Terminal(columns: 8, rows: 1)
        for start in stride(from: 1, through: 110_001, by: 1_000) {
            terminal.receive((start ..< start + 1_000).map { "\($0 + 10_000_000)\r\n" }.joined())
        }
        let removed = terminal.removedScrollbackCount
        let first = try #require(Int(text(of: terminal.scrollback[0], in: terminal)))
        terminal.resize(columns: 4, rows: 1)
        #expect(terminal.scrollback.count <= Terminal.Scrollback.maximumCount)
        let newFirst = try #require(
            Int(text(of: terminal.scrollback[0], in: terminal) + text(of: terminal.scrollback[1], in: terminal)))
        #expect(terminal.removedScrollbackCount - removed == 2 * (newFirst - first))
        #expect(text(of: terminal.scrollback[terminal.scrollback.count - 1], in: terminal) == "1000")
    }

    @Test func keepsTheLimitForOneLongLine() {
        var terminal = Terminal(columns: 1, rows: 1)
        terminal.receive(String(repeating: "a", count: Terminal.Scrollback.maximumCount + 2))
        #expect(terminal.scrollback.count <= Terminal.Scrollback.maximumCount)
        #expect(terminal.removedScrollbackCount + terminal.scrollback.count == Terminal.Scrollback.maximumCount + 1)
    }
}

private func text(of line: Terminal.Line, in terminal: Terminal) -> String {
    line.map(terminal.character(of:)).joined().trimmingCharacters(in: .whitespaces)
}
