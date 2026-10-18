import Testing

@testable import TerminalCore

struct LinkTests {
    @Test(arguments: ["\u{7}", "\u{1B}\\"])
    func setsTheLinkOfPrintedCells(terminator: String) {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;https://example.com/a;b\(terminator)ab\u{1B}]8;;\(terminator)c")
        #expect(
            uris(terminal.screen[0].prefix(3), in: terminal) == [
                "https://example.com/a;b", "https://example.com/a;b", nil,
            ])
    }

    @Test func keepsTheLinkAcrossAStyleReset() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;u\u{7}\u{1B}[1mx\u{1B}[0my\u{1B}]8;;\u{7}z")
        #expect(uris(terminal.screen[0].prefix(3), in: terminal) == ["u", "u", nil])
        #expect(!terminal.screen[0][1].style.isBold)
    }

    @Test func sharesALinkByItsIdentifierAndURI() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;id=1;u\u{7}a\u{1B}]8;;\u{7} \u{1B}]8;id=1;u\u{7}b\u{1B}]8;id=2;u\u{7}c")
        terminal.receive("\u{1B}]8;;v\u{7}d\u{1B}]8;;\u{7} \u{1B}]8;x=y:id=;v\u{7}e")
        let links = terminal.screen[0].map(\.style.link)
        #expect(links[0] == links[2])
        #expect(links[3] != links[2])
        #expect(links[4] == links[6])
        #expect(links[0] != 0 && links[3] != 0 && links[4] != 0)
    }

    @Test(arguments: ["\u{1B}]8;u\u{7}", "\u{1B}]8\u{7}", "\u{1B}]8;\u{7}"])
    func ignoresAMalformedLink(sequence: String) {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;u\u{7}a" + sequence + "b")
        #expect(uris(terminal.screen[0].prefix(2), in: terminal) == ["u", "u"])
    }

    @Test func erasesTheLink() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;u\u{7}abc\u{1B}[2K\u{1B}[3X")
        #expect(terminal.screen[0].allSatisfy { $0.style.link == 0 })
    }

    @Test func keepsTheLinkThroughAReflow() {
        var terminal = Terminal(columns: 4, rows: 4)
        terminal.receive("x\u{1B}]8;;u\u{7}abcdef\u{1B}]8;;\u{7}y\r\n")
        terminal.resize(columns: 10, rows: 4)
        #expect(uris(terminal.screen[0].prefix(8), in: terminal) == [nil, "u", "u", "u", "u", "u", "u", nil])
    }

    @Test func compactsTheLinksWhenTheTableIsFull() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.links = Terminal.Links(capacity: 80)
        terminal.receive("\u{1B}]8;;kept\u{7}k\u{1B}]8;;\u{7}\u{1B}7\r\n")
        for index in 0 ..< 200 {
            terminal.receive("\u{1B}]8;;\(index)\u{7}x\u{1B}]8;;\u{7}\u{1B}[2K\r")
        }
        terminal.receive("\u{1B}]8;;new\u{7}n\u{1B}8\u{1B}]8;;last\u{7}l")
        #expect(terminal.links.count < 80)
        #expect(uris(terminal.screen[0].prefix(1), in: terminal) == ["kept"])
        #expect(uris(terminal.screen[0].dropFirst().prefix(1), in: terminal) == ["last"])
    }

    @Test func keepsTheLinkOfTheSavedCursorThroughACompaction() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.links = Terminal.Links(capacity: 80)
        terminal.receive("\u{1B}]8;;saved\u{7}\u{1B}7\u{1B}]8;;\u{7}")
        for index in 0 ..< 200 {
            terminal.receive("\u{1B}]8;;\(index)\u{7}x\u{1B}]8;;\u{7}\u{1B}[2K\r")
        }
        terminal.receive("\u{1B}8s")
        #expect(uris(terminal.screen[0].prefix(1), in: terminal) == ["saved"])
    }

    @Test func keepsTheLinksOfTheNormalScreenThroughACompaction() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.links = Terminal.Links(capacity: 80)
        terminal.receive("\u{1B}]8;;normal\u{7}n\u{1B}]8;;\u{7}\u{1B}[?1049h")
        for index in 0 ..< 200 {
            terminal.receive("\u{1B}]8;;\(index)\u{7}x\u{1B}]8;;\u{7}\u{1B}[2K\r")
        }
        terminal.receive("\u{1B}[?1049l")
        #expect(terminal.links.count < 80)
        #expect(uris(terminal.screen[0].prefix(1), in: terminal) == ["normal"])
    }

    @Test func dropsLinksOverTheByteLimit() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.links = Terminal.Links(byteCapacity: 10)
        terminal.receive("\u{1B}]8;;12345\u{7}a\u{1B}]8;;67890\u{7}b\u{1B}]8;;x\u{7}c")
        #expect(uris(terminal.screen[0].prefix(3), in: terminal) == ["12345", "67890", nil])
    }

    @Test func keepsTheLinksOfTheScrollbackAfterAReset() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}]8;;u\u{7}a\r\n\u{1B}cb")
        #expect(uris(terminal.scrollback[0].prefix(1), in: terminal) == ["u"])
        #expect(uris(terminal.screen[0].prefix(1), in: terminal) == [nil])
    }

    @Test func showsNewLinksInTheScrollbackDuringAnUpdate() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}[?2026h\u{1B}]8;;u\u{7}a\r\nb")
        let displayed = terminal.displayed
        #expect(uris(displayed.scrollback[0].prefix(1), in: displayed) == ["u"])
    }

    @Test func keepsTheCellSmall() {
        #expect(MemoryLayout<Terminal.Cell>.stride == 16)
    }
}

private func uris(_ cells: some Sequence<Terminal.Cell>, in terminal: Terminal) -> [String?] {
    cells.map { terminal.links.uri(of: $0.style.link) }
}
