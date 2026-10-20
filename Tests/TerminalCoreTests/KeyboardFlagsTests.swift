import Testing

@testable import TerminalCore

struct KeyboardFlagsTests {
    @Test func startsWithoutFlags() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[?u") == "\u{1B}[?0u")
        #expect(!terminal.usesDisambiguatedKeys)
    }

    @Test func pushesAndPopsFlags() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[>1u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.usesDisambiguatedKeys)
        #expect(terminal.receive("\u{1B}[>0u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(!terminal.usesDisambiguatedKeys)
        #expect(terminal.receive("\u{1B}[<u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[<5u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[<u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[>1u\u{1B}[>0u\u{1B}[>0u\u{1B}[<2u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[>0u\u{1B}[<0u\u{1B}[?u") == "\u{1B}[?0u")
    }

    @Test func keepsOnlyTheSupportedFlags() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[>31u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[>30u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[=31u\u{1B}[?u") == "\u{1B}[?1u")
    }

    @Test func setsFlags() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[=0;2u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[=1u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[=1;3u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[=1;2u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[=0;2u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[=0;3u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[=0;4u\u{1B}[?u") == "\u{1B}[?1u")
        #expect(terminal.receive("\u{1B}[=0u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[=1u\u{1B}[<u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[>1u\u{1B}[=0u\u{1B}[<u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[=1u\u{1B}[=0;0u\u{1B}[?u") == "\u{1B}[?1u")
    }

    @Test func evictsTheOldestEntry() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[>1u" + String(repeating: "\u{1B}[>0u", count: 7))
        #expect(terminal.receive("\u{1B}[<7u\u{1B}[?u") == "\u{1B}[?1u")
        terminal.receive("\u{1B}[>1u" + String(repeating: "\u{1B}[>0u", count: 8))
        #expect(terminal.receive("\u{1B}[<7u\u{1B}[?u") == "\u{1B}[?0u")
        #expect(terminal.receive("\u{1B}[<u\u{1B}[?u") == "\u{1B}[?0u")
    }

    @Test func keepsAStackForEachScreen() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[>1u\u{1B}[?1049h")
        #expect(!terminal.usesDisambiguatedKeys)
        #expect(terminal.receive("\u{1B}[?u\u{1B}[>1u\u{1B}[>0u\u{1B}[?1049l") == "\u{1B}[?0u")
        #expect(terminal.usesDisambiguatedKeys)
        terminal.receive("\u{1B}[<u\u{1B}[?1049h")
        #expect(terminal.receive("\u{1B}[<u\u{1B}[?u") == "\u{1B}[?1u")
    }

    @Test func clearsTheFlagsOnReset() {
        var terminal = Terminal(columns: 4, rows: 2)
        terminal.receive("\u{1B}[>1u\u{1B}[?1049h\u{1B}[>1u\u{1B}c")
        #expect(!terminal.usesDisambiguatedKeys)
        #expect(terminal.receive("\u{1B}[?1049h\u{1B}[?u") == "\u{1B}[?0u")
    }

    @Test func answersTheQueryBeforeTheDeviceAttributes() {
        var terminal = Terminal(columns: 4, rows: 2)
        #expect(terminal.receive("\u{1B}[?u\u{1B}[c") == "\u{1B}[?0u\u{1B}[?1;2c")
    }
}
