import Foundation
import Testing

@testable import TerminalCore

struct RestorationTests {
    private let prompt = "\u{1B}]133;A\u{7}$ \u{1B}]133;B\u{7}"

    private struct RestoredCell: Equatable {
        var character: Character
        var width: UInt8
        var style: Terminal.Style
        var link: String?
    }

    private func rows(of terminal: Terminal) -> [[RestoredCell]] {
        (terminal.scrollback + terminal.normalLines)
            .map { line in
                let end = line.isWrapped ? line.count : (line.lastIndex { !$0.isBlank } ?? -1) + 1
                return line.prefix(end)
                    .map { cell in
                        var style = cell.style
                        style.link = 0
                        return RestoredCell(
                            character: terminal.character(of: cell),
                            width: cell.width,
                            style: style,
                            link: terminal.links.uri(of: cell.style.link)
                        )
                    }
            }
    }

    private func wraps(of terminal: Terminal) -> [Bool] {
        (terminal.scrollback + terminal.normalLines).map(\.isWrapped)
    }

    private func restored(_ terminal: Terminal) -> Terminal {
        Terminal(restoring: terminal.restoration)
    }

    @Test func restoresTheTextAndTheStyles() {
        var terminal = Terminal(columns: 30, rows: 5)
        terminal.receive("plain \u{1B}[1;3;4;38;5;200;48;2;1;2;3mstyled\u{1B}[0m\r\n")
        terminal.receive("\u{1B}[2;7;8;9;31;103mflags\u{1B}[0m 中文 👨‍👩‍👧 🇧🇷 e\u{301}\r\n")
        terminal.receive("\u{1B}]8;;https://example.com\u{1B}\\link\u{1B}]8;;\u{1B}\\ \u{1B}(0qx\u{1B}(B\r\n")
        let restored = restored(terminal)
        #expect(rows(of: restored).prefix(3) == rows(of: terminal).prefix(3))
        #expect(rows(of: restored)[2].first?.link == "https://example.com")
    }

    @Test func restoresWrappedLines() {
        var terminal = Terminal(columns: 5, rows: 4)
        terminal.receive("abcdefgh\r\nabcd中x\r\n12345\r\n")
        let restored = restored(terminal)
        #expect(rows(of: restored).prefix(5) == rows(of: terminal).prefix(5))
        #expect(wraps(of: restored).prefix(5) == [true, false, true, false, false])
        #expect(restored.normalLines[0][4] == .padding)
    }

    @Test func endsAWrappedLineThatLostItsWideCharacter() {
        var terminal = Terminal(columns: 5, rows: 4)
        terminal.receive("abcd中\rx")
        let restored = restored(terminal)
        #expect(rows(of: restored).prefix(2).map { String($0.map(\.character)) } == ["abcd", "x"])
    }

    @Test func clearsTheRestOfAWrappedLine() {
        var terminal = Terminal(columns: 5, rows: 3)
        terminal.receive("1\r\n2\r\n3\r\n4\r\n\u{1B}[Habcde\u{1B}[41mfg\u{1B}[0m")
        let restored = restored(terminal)
        #expect(rows(of: restored) == rows(of: terminal).prefix(4) + [[]])
    }

    @Test func restoresTheScrollback() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive((0 ..< 12_000).map { "line \($0)\r\n" }.joined())
        let restored = restored(terminal)
        #expect(restored.removedScrollbackCount == 0)
        #expect(rows(of: restored).prefix(10_000) == rows(of: terminal).prefix(10_000))
    }

    @Test func doesNotRestoreThePendingPrompt() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}file\r\n\u{1B}]133;D;0\u{7}" + prompt)
        terminal.receive(String(repeating: "typed", count: 9))
        let restored = restored(terminal)
        #expect(rows(of: restored).count == restored.rows)
        #expect(rows(of: restored).prefix(3).map { String($0.map(\.character)) } == ["$ ls", "file", ""])
        #expect(restored.cursor == Terminal.Position(row: 2, column: 0))
    }

    @Test func keepsTheTextBeforeAPromptInTheSameLine() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "printf no\r\n\u{1B}]133;C\u{7}no\u{1B}]133;D;0\u{7}" + prompt)
        let restored = restored(terminal)
        #expect(rows(of: restored).prefix(3).map { String($0.map(\.character)) } == ["$ printf no", "no", ""])
    }

    @Test func keepsTheOutputAfterThePendingPrompt() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "sleep 1 &\r\n\u{1B}]133;C\u{7}[1] 7\r\n\u{1B}]133;D;0\u{7}" + prompt + "late\r\n")
        let restored = restored(terminal)
        #expect(
            rows(of: restored).prefix(4).map { String($0.map(\.character)) } == ["$ sleep 1 &", "[1] 7", "$ late", ""])
    }

    @Test func doesNotRestoreAWrappedInput() {
        var terminal = Terminal(columns: 10, rows: 5)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}\u{1B}]133;D;0\u{7}" + prompt + "echo one two")
        let restored = restored(terminal)
        #expect(rows(of: restored).prefix(2).map { String($0.map(\.character)) } == ["$ ls", ""])
    }

    @Test func keepsTheLastCharacterBeforeAPromptAtTheMargin() {
        for input in ["abcde" + prompt, "abcde\u{1B}]133;A\u{7}", "abc中\u{1B}]133;A\u{7}"] {
            var terminal = Terminal(columns: 5, rows: 3)
            terminal.receive(input)
            let text = rows(of: restored(terminal)).first.map { String($0.filter { $0.width > 0 }.map(\.character)) }
            #expect(text == String(input.prefix(4)) + (input.hasPrefix("abcde") ? "e" : ""))
        }
    }

    @Test func keepsAWideCharacterUnderAPromptMark() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("中x\u{1B}[2G\u{1B}]133;A\u{7}")
        #expect(rows(of: restored(terminal)).first?.map(\.character) == ["中", " "])
    }

    @Test func doesNotRestoreAPromptThatWraps() {
        var terminal = Terminal(columns: 3, rows: 3)
        terminal.receive("\u{1B}]133;A\u{7}ab$ ")
        #expect(rows(of: restored(terminal)).allSatisfy { $0.isEmpty })
    }

    @Test func keepsThePaddingOfAWrappedLine() {
        var terminal = Terminal(columns: 7, rows: 4)
        terminal.receive((0 ..< 8).map { "l\($0)\r\n" }.joined() + "\u{1B}[H\u{1B}[2J\u{1B}[41m")
        terminal.receive(String(repeating: "中", count: 8) + "\u{1B}[0m\r\nx\r\ny\r\nz\r\n")
        let restored = restored(terminal)
        let count = rows(of: terminal).count - 1
        #expect(Array(rows(of: restored).prefix(count)) == Array(rows(of: terminal).prefix(count)))
    }

    @Test func removesDirectoriesThatAreNotFiles() {
        let restored = Terminal(
            restoring: .init(
                columns: 10,
                rows: 3,
                content: Data(),
                commands: [Terminal.Command(directory: URL(string: "https://example.com"), isFinished: true)],
                removedCommandCount: 0,
                currentDirectory: nil
            )
        )
        #expect(restored.commands.first?.directory == nil)
    }

    @Test func restoresTheCommands() throws {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.receive("\u{1B}]7;file:///tmp\u{7}")
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C;cmdline_url=ls\u{7}a\r\nb\r\nc\r\n\u{1B}]133;D;1\u{7}")
        terminal.receive(prompt + "sleep 9\r\n\u{1B}]133;C\u{7}")
        let restored = restored(terminal)
        #expect(restored.currentDirectory == URL(string: "file:///tmp"))
        #expect(restored.commands.map(\.text) == ["ls", "sleep 9"])
        #expect(restored.commands.map(\.exitStatus) == [1, nil])
        #expect(restored.commands.allSatisfy { $0.isFinished })
        let first = try #require(restored.commands.first)
        #expect(first.prompt == Terminal.Position(row: 0, column: 0))
        #expect(first.output == Terminal.Position(row: 1, column: 0))
        #expect(first.end == Terminal.Position(row: 4, column: 0))
        #expect(restored.commands.last?.end == Terminal.Position(row: 5, column: 0))
    }

    @Test func movesTheMarksWithTheRemovedScrollback() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive((0 ..< 12_000).map { "line \($0)\r\n" }.joined())
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}out\r\n\u{1B}]133;D;0\u{7}")
        let restored = restored(terminal)
        let row = restored.commands.last?.output?.row
        #expect(row.map { String(rows(of: restored)[$0].map(\.character)) } == "out")
    }

    @Test func restoresTheNormalScreenBehindTheAlternateScreen() {
        var terminal = Terminal(columns: 10, rows: 3)
        terminal.receive("normal\r\n\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?2004h\u{1B}[?25lfull")
        let restored = restored(terminal)
        #expect(!restored.isAlternateScreenActive)
        #expect(rows(of: restored).first.map { String($0.map(\.character)) } == "normal")
        #expect(restored.mouseTracking == .off)
        #expect(!restored.usesBracketedPaste)
        #expect(restored.isCursorVisible)
    }

    @Test func doesNotRestoreModesFromTheContent() {
        let modes =
            "\u{1B}[?1049h\u{1B}[?7l\u{1B}[4h\u{1B}[2;3r\u{1B}[?2026h\u{1B}[31m\u{1B}]8;;x:y\u{1B}\\\u{1B}(0\u{1B}]2;abc"
        var terminal = Terminal(
            restoring: .init(
                columns: 10,
                rows: 4,
                content: Data(("text\r\n" + modes).utf8),
                commands: [],
                removedCommandCount: 0,
                currentDirectory: nil
            )
        )
        #expect(!terminal.isSynchronizingOutput)
        #expect(terminal.title.isEmpty)
        terminal.receive("qqqqqqqqqqqq")
        #expect(rows(of: terminal).prefix(3).map { String($0.map(\.character)) } == ["text", "qqqqqqqqqq", "qq"])
        #expect(terminal.normalLines[1][0].style == Terminal.Style())
    }

    @Test func printsBelowTheRestoredContent() {
        var terminal = Terminal(columns: 10, rows: 4)
        terminal.receive("one\r\ntwo")
        var restored = restored(terminal)
        restored.receive("new")
        #expect(rows(of: restored).prefix(3).map { String($0.map(\.character)) } == ["one", "two", "new"])
    }

    @Test func restoresAnEmptyTerminal() {
        let restored = restored(Terminal(columns: 10, rows: 4))
        #expect(restored.cursor == Terminal.Position(row: 0, column: 0))
        #expect(restored.scrollback.isEmpty)
        #expect(rows(of: restored).allSatisfy { $0.isEmpty })
    }

    @Test func clampsDamagedValues() {
        let command = Terminal.Command(
            text: "x",
            prompt: Terminal.Position(row: -5, column: 3),
            output: Terminal.Position(row: 1, column: -9),
            end: Terminal.Position(row: Int.max, column: Int.max)
        )
        let restored = Terminal(
            restoring: .init(
                columns: Int.max,
                rows: 0,
                content: Data("a\r\nb\r\n".utf8),
                commands: Array(repeating: command, count: 10_005),
                removedCommandCount: Int.max,
                currentDirectory: URL(string: "https://example.com")
            )
        )
        #expect(restored.columns == 1_000)
        #expect(restored.rows == 1)
        #expect(restored.commands.count == 10_000)
        #expect(restored.removedCommandCount == (1 << 40) + 5)
        #expect(restored.currentDirectory == nil)
        let first = restored.commands.first
        #expect(first?.prompt == nil)
        #expect(first?.output == Terminal.Position(row: 1, column: 0))
        #expect(first?.end == Terminal.Position(row: 2, column: 0))
        #expect(first?.isFinished == true)
    }

    @Test func encodesAndDecodes() throws {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file:///tmp\u{7}" + prompt + "ls\r\n\u{1B}]133;C\u{7}\u{1B}[31m中\u{1B}[0m\r\n")
        let restoration = terminal.restoration
        let json = try JSONDecoder().decode(Terminal.Restoration.self, from: JSONEncoder().encode(restoration))
        #expect(json == restoration)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let list = try PropertyListDecoder().decode(Terminal.Restoration.self, from: encoder.encode(restoration))
        #expect(list == restoration)
    }

    @Test func reachesAFixedPointForRandomOutput() {
        var generator = SeededGenerator(seed: 7)
        let pieces = [
            "a", "中", "👨‍👩‍👧", "e\u{301}", " ", "\t", "\r", "\n", "\u{8}", "\u{1B}[31m", "\u{1B}[0m", "\u{1B}[48;5;9m",
            "\u{1B}[K", "\u{1B}[2J", "\u{1B}[H", "\u{1B}[3;2H", "\u{1B}[?1049h", "\u{1B}[?1049l", "\u{1B}[2;3r",
            "\u{1B}[L", "\u{1B}[M", "\u{1B}[3@", "\u{1B}[2P", "\u{1B}M", "\u{1B}]8;;u\u{1B}\\", "\u{1B}]8;;\u{1B}\\",
            "\u{1B}c", "\u{1B}[?7l", "\u{1B}[?7h", "\u{1B}[4h", "\u{1B}[4l", "\u{1B}[5b", "\u{1B}]133;A\u{7}",
            "\u{1B}]133;C\u{7}", "\u{1B}]133;D;2\u{7}",
        ]
        for _ in 0 ..< 300 {
            var terminal = Terminal(columns: Int.random(in: 1 ... 12, using: &generator), rows: 4)
            for _ in 0 ..< 200 {
                terminal.receive(pieces.randomElement(using: &generator)!)
            }
            let once = restored(terminal)
            let twice = restored(once)
            #expect(rows(of: twice) == rows(of: once))
            #expect(wraps(of: twice) == wraps(of: once))
            #expect(twice.commands == once.commands)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ value >> 30) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ value >> 27) &* 0x94D0_49BB_1331_11EB
        return value ^ value >> 31
    }
}
