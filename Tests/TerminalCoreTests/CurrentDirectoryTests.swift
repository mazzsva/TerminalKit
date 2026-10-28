import Foundation
import Testing

@testable import TerminalCore

struct CurrentDirectoryTests {
    @Test func setsTheCurrentDirectory() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file:///Users/me/a%20b%C3%A9\u{7}")
        #expect(terminal.currentDirectory == URL(filePath: "/Users/me/a bé"))

        terminal.receive("\u{1B}]7;https://example.com/\u{7}\u{1B}]7;not a url\u{7}")
        #expect(terminal.currentDirectory == URL(filePath: "/Users/me/a bé"))
    }

    @Test func setsTheCurrentDirectoryOfThisMac() throws {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        try #require(gethostname(&name, Int(MAXHOSTNAMELEN)) == 0)
        let host = String(decoding: name.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        for location in ["file://\(host)/a", "file://\(host.uppercased())/a", "file://localhost/a", "file:///a"] {
            var terminal = Terminal(columns: 20, rows: 5)
            terminal.receive("\u{1B}]7;\(location)\u{7}")
            #expect(terminal.currentDirectory == URL(filePath: "/a"))
            #expect(terminal.currentDirectory?.host() == nil)
        }
    }

    @Test func forgetsTheCurrentDirectoryOfAnotherHost() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file:///a\u{7}\u{1B}]7;file://server.example.com/home/me\u{7}")
        #expect(terminal.currentDirectory == nil)
        terminal.receive("\u{1B}]7;file:///a\u{7}\u{1B}]7;file://localhost\u{7}")
        #expect(terminal.currentDirectory == nil)
        terminal.receive("\u{1B}]7;file:///a\u{7}\u{1B}]7;file://%FF/a\u{7}")
        #expect(terminal.currentDirectory == nil)
    }

    @Test func ignoresACurrentDirectoryOverTheLengthLimit() {
        let path = "/" + String(repeating: "a", count: 4_086)
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file:///a\u{7}\u{1B}]7;file://\(path)b\u{7}c")
        #expect(terminal.currentDirectory == URL(filePath: "/a"))
        #expect(terminal.character(of: terminal.screen[0][0]) == "c")
        terminal.receive("\u{1B}]7;file://\(path)\u{7}")
        #expect(terminal.currentDirectory == URL(filePath: path))
    }

    @Test func keepsTheCurrentDirectoryAfterAReset() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file:///a\u{7}ls\r\n\u{1B}c")
        #expect(terminal.currentDirectory == URL(string: "file:///a"))
    }
}
