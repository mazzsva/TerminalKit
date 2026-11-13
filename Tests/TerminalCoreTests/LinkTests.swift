import Testing

@testable import TerminalCore

struct LinkTests {
    @Test(arguments: ["\u{7}", "\u{1B}\\"])
    func setsTheLinkOfPrintedCells(terminator: String) {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;https://example.com/a;b\(terminator)a b\u{1B}]8;;\(terminator)c")
        #expect(
            uris(terminal.screen[0].prefix(4), in: terminal) == [
                "https://example.com/a;b", "https://example.com/a;b", "https://example.com/a;b", nil,
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
        let links = terminal.screen[0].map(\.link)
        #expect(links[0] == links[2])
        #expect(links[3] != links[2])
        #expect(links[4] == links[6])
        #expect(links[0] != 0 && links[3] != 0 && links[4] != 0)
    }

    @Test func sharesTheLinkOfAnAddressThatClaudeCodeWraps() {
        var terminal = Terminal(columns: 20, rows: 3)
        let open = "\u{1B}]8;id=57yy2o;https://example.com/long\u{7}"
        terminal.receive("  \(open)https://\u{1B}]8;;\u{7}\r\n  \(open)example.com/long\u{1B}]8;;\u{7}\r\n")
        let first = terminal.screen[0].map(\.link)
        let second = terminal.screen[1].map(\.link)
        #expect(first[2] != 0)
        #expect(first[..<2].allSatisfy { $0 == 0 } && first[2 ..< 10].allSatisfy { $0 == first[2] })
        #expect(second[..<2].allSatisfy { $0 == 0 } && second[2 ..< 18].allSatisfy { $0 == first[2] })
        #expect(first[10] == 0 && second[18] == 0)
        #expect(terminal.links.uri(of: first[2]) == "https://example.com/long")
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
        #expect(terminal.screen[0].allSatisfy { $0.link == 0 })
    }

    @Test func keepsAnOpenLinkAfterTheScreenClears() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;u\u{7}abc\u{1B}[2J\u{1B}[H")
        #expect(terminal.screen.allSatisfy { $0.allSatisfy { $0.link == 0 } })
        terminal.receive("d\u{1B}]8;;\u{7}e")
        #expect(uris(terminal.screen[0].prefix(3), in: terminal) == ["u", nil, nil])
    }

    @Test func movesTheLinkWithInsertedAndDeletedCharacters() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;u\u{7}ab\u{1B}]8;;\u{7}c\u{1B}[H\u{1B}[2@")
        #expect(uris(terminal.screen[0].prefix(5), in: terminal) == [nil, nil, "u", "u", nil])
        terminal.receive("\u{1B}[3P")
        #expect(uris(terminal.screen[0].prefix(3), in: terminal) == ["u", nil, nil])
    }

    @Test func linksBothCellsOfAWideCharacter() {
        var terminal = Terminal(columns: 10, rows: 2)
        terminal.receive("\u{1B}]8;;u\u{7}\u{4E2D}\u{1B}]8;;\u{7}")
        #expect(uris(terminal.screen[0].prefix(3), in: terminal) == ["u", "u", nil])
    }

    @Test func keepsTheLinkThroughAReflow() {
        var terminal = Terminal(columns: 4, rows: 4)
        terminal.receive("x\u{1B}]8;;u\u{7}abcdef\u{1B}]8;;\u{7}y\r\n")
        terminal.resize(columns: 10, rows: 4)
        #expect(uris(terminal.screen[0].prefix(8), in: terminal) == [nil, "u", "u", "u", "u", "u", "u", nil])
    }

    @Test func keepsTheLinkInTheSavedLines() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("x\u{1B}]8;;u\u{7}abcdef\u{1B}]8;;\u{7}y\r\n\r\n")
        #expect(terminal.scrollback.count == 2)
        for columns in [3, 10, 4] {
            terminal.resize(columns: columns, rows: 2)
            let cells = (Array(terminal.scrollback) + terminal.screen).joined().filter(\.isWritten)
            #expect(cells.map(terminal.character(of:)).joined() == "xabcdefy")
            #expect(uris(cells, in: terminal) == [nil, "u", "u", "u", "u", "u", "u", nil])
        }
        #expect(terminal.scrollback.count == 2)
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
        #expect(uris(terminal.screen[0].prefix(2), in: terminal) == ["kept", "last"])
    }

    @Test func waitsLongerAfterACompactionThatFreesNothing() {
        var links = Terminal.Links(capacity: 80)
        var compactions = 0
        for index in 0 ..< 2_000 {
            if links.needsCompaction(forKey: "\(index)") {
                _ = links.compact(keeping: Array(repeating: true, count: links.count))
                compactions += 1
            }
            _ = links.link(forKey: "\(index)", uri: "\(index)")
        }
        #expect(links.count == 80)
        #expect((5 ... 25).contains(compactions))
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

    @Test func keepsTheDisplayedLinksThroughACompaction() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.links = Terminal.Links(capacity: 80)
        terminal.receive("\u{1B}]8;;shown\u{7}s\u{1B}]8;;\u{7}\r\n\u{1B}[?2026h\u{1B}[2J")
        for index in 0 ..< 200 {
            terminal.receive("\u{1B}]8;;\(index)\u{7}x\u{1B}]8;;\u{7}\u{1B}[2K\r")
        }
        let displayed = terminal.displayed
        #expect(terminal.links.count < 80)
        #expect(uris(displayed.screen[0].prefix(1), in: displayed) == ["shown"])
    }

    @Test func dropsLinksOverTheByteLimit() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.links = Terminal.Links(byteCapacity: 10)
        terminal.receive("\u{1B}]8;;12345\u{7}a\u{1B}]8;;67890\u{7}b\u{1B}]8;;x\u{7}c")
        #expect(uris(terminal.screen[0].prefix(3), in: terminal) == ["12345", "67890", nil])
    }

    @Test func countsTheLinkIdentifiersInTheByteLimit() {
        var terminal = Terminal(columns: 80, rows: 24)
        terminal.links = Terminal.Links(byteCapacity: 10_000)
        let id = String(repeating: "\u{10FFFD}", count: 250)
        var linked = 0
        for index in 0 ..< 100 {
            terminal.receive("\u{1B}[2K\r\u{1B}]8;id=\(index)\(id);x\u{7}a\u{1B}]8;;\u{7}")
            linked += terminal.screen[0][0].link == 0 ? 0 : 1
        }
        #expect(terminal.links.count <= terminal.links.byteCapacity / id.utf8.count)
        #expect(linked > terminal.links.byteCapacity / id.utf8.count)
    }

    @Test func keepsTheLinkIdentifierBytesThroughACompaction() {
        var terminal = Terminal(columns: 80, rows: 24)
        terminal.links = Terminal.Links(byteCapacity: 10_000)
        let id = String(repeating: "\u{10FFFD}", count: 250)
        for index in 0 ..< 200 {
            terminal.receive("\u{1B}]8;id=\(index)\(id);x\u{7}a\u{1B}]8;;\u{7}")
        }
        #expect(terminal.links.count <= terminal.links.byteCapacity / id.utf8.count)
    }

    @Test func keepsTheLinksOfTheScrollbackAfterAReset() {
        var terminal = Terminal(columns: 10, rows: 1)
        terminal.receive("\u{1B}]8;;u\u{7}a\r\n\u{1B}cb")
        #expect(uris(terminal.scrollback[0].prefix(1), in: terminal) == ["u"])
        #expect(uris(terminal.screen[0].prefix(1), in: terminal) == [nil])
    }
}

private func uris(_ cells: some Sequence<Terminal.Cell>, in terminal: Terminal) -> [String?] {
    cells.map { terminal.links.uri(of: $0.link) }
}
