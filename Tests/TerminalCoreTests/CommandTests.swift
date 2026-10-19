import Foundation
import Testing

@testable import TerminalCore

struct CommandTests {
    private let prompt = "\u{1B}]133;A\u{7}$ \u{1B}]133;B\u{7}"

    @Test func recordsACommand() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file://localhost/Users/me\u{7}" + prompt + "ls\r\n\u{1B}]133;C;cmdline_url=ls\u{7}")
        #expect(terminal.commands.count == 1)
        #expect(terminal.commands.last?.isFinished == false)

        terminal.receive("file\r\n\u{1B}]133;D;0\u{7}")
        let command = terminal.commands.last
        #expect(command?.text == "ls")
        #expect(command?.directory == URL(filePath: "/Users/me"))
        #expect(command?.exitStatus == 0)
        #expect(command?.isFinished == true)
        #expect(command?.prompt == Terminal.Position(row: 0, column: 0))
        #expect(command?.output == Terminal.Position(row: 1, column: 0))
        #expect(command?.end == Terminal.Position(row: 2, column: 0))
    }

    @Test func readsTheCommandFromTheScreen() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "ls  -la  \r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.text == "ls  -la")
    }

    @Test func readsAWrappedCommandFromTheScreen() {
        var terminal = Terminal(columns: 6, rows: 5)
        terminal.receive(prompt + "echo hello world\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.text == "echo hello world")
    }

    @Test func readsAWideCommandFromTheScreen() {
        var terminal = Terminal(columns: 5, rows: 5)
        terminal.receive(prompt + "ab中文\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.text == "ab中文")
    }

    @Test func readsAMultilineCommandFromTheScreen() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "for x in a\r\n> do\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.text == "for x in a\n> do")
    }

    @Test func readsACommandOnTheLineOfTheCursor() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "ls\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.text == "ls")
    }

    @Test func readsNoTextWithoutTheInputMark() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("$ ls\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.count == 1)
        #expect(terminal.commands.last?.text == nil)
        #expect(terminal.commands.last?.prompt == nil)
    }

    @Test func usesTheInputMarkWithoutAPromptMark() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\r\n$ \u{1B}]133;B\u{7}ls\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.prompt == Terminal.Position(row: 1, column: 2))
        #expect(terminal.commands.last?.text == "ls")
    }

    @Test func usesEachPromptForOneCommand() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}x\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.count == 2)
        #expect(terminal.commands[1].prompt == nil)
        #expect(terminal.commands[1].text == nil)
    }

    @Test func readsNoTextForAnEmptyCommand() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "   \r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.text == nil)
    }

    @Test(arguments: [
        ("echo%20%C3%A9%3B%25", "echo é;%"),
        ("a%0Ab", "a\nb"),
        ("", "typed"),
        ("%ZZ", "typed"),
        ("%C3", "typed"),
    ])
    func decodesTheCommandURL(url: String, text: String) {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "typed\r\n\u{1B}]133;C;cmdline_url=\(url)\u{7}")
        #expect(terminal.commands.last?.text == text)
    }

    @Test func takesTheURLAfterOtherParameters() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "typed\r\n\u{1B}]133;C;aid=1;cmdline_url=ls\u{7}")
        #expect(terminal.commands.last?.text == "ls")
    }

    @Test(arguments: [
        ("D;130", Int32(130)), ("D", nil), ("D;", nil), ("D;x", nil), ("D;99999999999", nil), ("D;-1", -1),
    ])
    func readsTheExitStatus(mark: String, status: Int32?) {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "x\r\n\u{1B}]133;C\u{7}\u{1B}]133;\(mark)\u{7}")
        #expect(terminal.commands.last?.isFinished == true)
        #expect(terminal.commands.last?.exitStatus == status)
    }

    @Test func finishesACommandAtTheNextPrompt() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "exec zsh\r\n\u{1B}]133;C\u{7}" + prompt)
        #expect(terminal.commands.last?.isFinished == true)
        #expect(terminal.commands.last?.exitStatus == nil)
        #expect(terminal.commands.last?.end == Terminal.Position(row: 1, column: 0))
    }

    @Test func finishesACommandAtTheNextCommand() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "a\r\n\u{1B}]133;C\u{7}\u{1B}]133;C;cmdline_url=b\u{7}")
        #expect(terminal.commands.count == 2)
        #expect(terminal.commands.first?.isFinished == true)
        #expect(terminal.commands.last?.text == "b")
        #expect(terminal.commands.last?.isFinished == false)
    }

    @Test func keepsTheStatusOfAFinishedCommand() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "a\r\n\u{1B}]133;C\u{7}\u{1B}]133;D;1\u{7}\u{1B}]133;D;2\u{7}" + prompt)
        #expect(terminal.commands.count == 1)
        #expect(terminal.commands.last?.exitStatus == 1)
        #expect(terminal.commands.last?.end == Terminal.Position(row: 1, column: 0))
    }

    @Test func ignoresAnEndWithoutACommand() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]133;D;0\u{7}" + prompt)
        #expect(terminal.commands.isEmpty)
    }

    @Test(arguments: [
        "\u{1B}]133\u{7}", "\u{1B}]133;\u{7}", "\u{1B}]133;Z\u{7}", "\u{1B}]133;;;\u{7}", "\u{1B}]7\u{7}",
    ])
    func ignoresAnUnknownMark(mark: String) {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(mark + "x")
        #expect(terminal.commands.isEmpty)
        #expect(terminal.currentDirectory == nil)
        #expect(terminal.character(of: terminal.screen[0][0]) == "x")
    }

    @Test func usesTheLastPromptOfARedraw() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "\r\n" + prompt + "ls\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.prompt == Terminal.Position(row: 1, column: 0))
        #expect(terminal.commands.last?.text == "ls")
    }

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
    }

    @Test func keepsTheMarksOnTheirLinesWhenTheScreenScrolls() {
        var terminal = Terminal(columns: 20, rows: 3)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}1\r\n2\r\n3\r\n4\r\n\u{1B}]133;D;0\u{7}" + prompt)
        let command = terminal.commands[0]
        #expect(text(at: command.prompt, in: terminal) == "$ ls")
        #expect(text(at: command.output, in: terminal) == "1")
        #expect(command.end == Terminal.Position(row: 5, column: 0))
        #expect(text(at: command.end, in: terminal) == "$")
    }

    @Test(arguments: [3, 4, 7, 13, 40])
    func movesTheMarksWithTheText(columns: Int) {
        var terminal = Terminal(columns: 10, rows: 4)
        for name in ["first", "second", "third"] {
            terminal.receive(
                prompt + "echo \(name)\r\n\u{1B}]133;C\u{7}\(name) output is long\r\n\u{1B}]133;D;0\u{7}"
            )
        }
        terminal.receive(prompt)
        terminal.resize(columns: columns, rows: 4)
        for (command, name) in zip(terminal.commands, ["first", "second", "third"]) {
            #expect(text(at: command.prompt, in: terminal).hasPrefix("$"))
            #expect(text(at: command.output, in: terminal).hasPrefix(String(name.prefix(columns))))
            #expect(text(at: command.end, in: terminal).hasPrefix("$"))
        }
    }

    @Test func movesTheMarksOnTheAlternateScreen() {
        var terminal = Terminal(columns: 10, rows: 4)
        terminal.receive(prompt + "echo 1\r\n\u{1B}]133;C\u{7}long output\r\n\u{1B}]133;D;0\u{7}" + prompt + "vim\r\n")
        terminal.receive("\u{1B}]133;C\u{7}\u{1B}[?1049h")
        terminal.resize(columns: 4, rows: 4)
        terminal.receive("\u{1B}[?1049l")
        #expect(text(at: terminal.commands[0].output, in: terminal) == "long")
        #expect(text(at: terminal.commands[1].prompt, in: terminal) == "$ vi")
    }

    @Test func recordsNoPositionsOnTheAlternateScreen() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}[?1049h" + prompt + "ls\r\n\u{1B}]133;C;cmdline_url=ls\u{7}\u{1B}]133;D;0\u{7}")
        #expect(terminal.commands.last?.text == "ls")
        #expect(terminal.commands.last?.prompt == nil)
        #expect(terminal.commands.last?.output == nil)
        #expect(terminal.commands.last?.end == nil)
    }

    @Test func forgetsTheMarksOfAClearedScreen() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("a\r\n" + prompt + "ls\r\n\u{1B}]133;C\u{7}x\r\n\u{1B}]133;D;0\u{7}\u{1B}[H\u{1B}[2J")
        #expect(terminal.commands[0].prompt == nil)
        #expect(terminal.commands[0].output == nil)
        #expect(terminal.commands[0].text == "ls")
    }

    @Test func forgetsTheMarksBelowAnEraseFromTheCursor() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}x\r\n\u{1B}]133;D;0\u{7}\u{1B}[2;3H\u{1B}[J")
        #expect(terminal.commands[0].prompt == Terminal.Position(row: 0, column: 0))
        #expect(terminal.commands[0].output == Terminal.Position(row: 1, column: 0))
        #expect(terminal.commands[0].end == nil)
    }

    @Test func keepsTheMarksOfTheScrollbackWhenTheScreenIsCleared() {
        var terminal = Terminal(columns: 20, rows: 2)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}1\r\n2\r\n3\u{1B}[2J")
        #expect(text(at: terminal.commands[0].prompt, in: terminal) == "$ ls")
        #expect(terminal.commands[0].output == Terminal.Position(row: 1, column: 0))
    }

    @Test func dropsTheMarksOfAClearedScrollback() {
        var terminal = Terminal(columns: 20, rows: 2)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}1\r\n2\r\n3\u{1B}[3J")
        #expect(terminal.removedScrollbackCount == 2)
        #expect(text(at: terminal.commands[0].prompt, in: terminal) == "")
    }

    @Test func keepsTheCommandsAfterAReset() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7;file:///a\u{7}" + prompt + "ls\r\n\u{1B}]133;C\u{7}\u{1B}c")
        #expect(terminal.commands.count == 1)
        #expect(terminal.commands[0].prompt == nil)
        #expect(terminal.currentDirectory == URL(string: "file:///a"))

        terminal.receive("\u{1B}]133;D;0\u{7}")
        #expect(terminal.commands[0].exitStatus == 0)
    }

    @Test func keepsTheMarksOfTheScrollbackAfterAReset() {
        var terminal = Terminal(columns: 20, rows: 2)
        terminal.receive(prompt + "ls\r\n\u{1B}]133;C\u{7}1\r\n2\r\n3\r\n4\u{1B}[3J5\r\n6\r\n7\u{1B}c")
        #expect(terminal.commands[0].prompt == Terminal.Position(row: 0, column: 0))
        #expect(terminal.removedScrollbackCount == 3)

        terminal.receive(prompt + "x\r\n\u{1B}]133;C\u{7}a\r\nb\r\nc\u{1B}c")
        #expect(text(at: terminal.commands[1].prompt, in: terminal) == "$ x")
        #expect(text(at: terminal.commands[1].output, in: terminal) == "a")
    }

    @Test func keepsTheRowsOfThePromptForTheShell() {
        var terminal = Terminal(columns: 30, rows: 6)
        terminal.receive("long output line that wraps\r\n\u{1B}]133;A\u{7}top line of a long prompt\r\n% ")
        terminal.receive("\u{1B}]133;B\u{7}echo abc")
        terminal.resize(columns: 10, rows: 6)
        #expect(screenLines(terminal) == ["long outpu", "t line tha", "t wraps", "top line o", "% echo abc", ""])
        #expect(terminal.cursor == Terminal.Position(row: 4, column: 9))

        terminal.resize(columns: 12, rows: 6)
        #expect(screenLines(terminal) == ["long output", "line that wr", "aps", "top line o", "% echo abc", ""])
    }

    @Test func reflowsThePromptAboveASecondaryMark() {
        var terminal = Terminal(columns: 30, rows: 6)
        terminal.receive("\u{1B}]133;A\u{7}top line of a long prompt\r\n\u{1B}]133;A;k=s\u{7}% ")
        terminal.receive("\u{1B}]133;B\u{7}echo abc")
        terminal.resize(columns: 10, rows: 6)
        #expect(screenLines(terminal) == ["top line o", "f a long p", "rompt", "% echo abc", "", ""])

        terminal.receive("\r\n\u{1B}]133;C\u{7}")
        #expect(terminal.commands.last?.prompt == Terminal.Position(row: 0, column: 0))
        #expect(terminal.commands.last?.text == "echo abc")
    }

    @Test func reflowsThePromptOfARunningCommand() {
        var terminal = Terminal(columns: 30, rows: 6)
        terminal.receive("\u{1B}]133;A\u{7}top line of a long prompt\r\n% ")
        terminal.receive("\u{1B}]133;B\u{7}cat\r\n\u{1B}]133;C\u{7}")
        terminal.resize(columns: 10, rows: 6)
        #expect(screenLines(terminal) == ["top line o", "f a long p", "rompt", "% cat", "", ""])
    }

    @Test func reflowsAPromptThatStartsInTheScrollback() {
        var terminal = Terminal(columns: 30, rows: 2)
        terminal.receive("\u{1B}]133;A\u{7}top line of a long prompt\r\nsecond\r\n% \u{1B}]133;B\u{7}ls")
        terminal.resize(columns: 10, rows: 2)
        #expect(scrollbackLines(terminal) == ["top line o", "f a long p", "rompt"])
        #expect(screenLines(terminal) == ["second", "% ls"])
    }

    @Test func forgetsThePromptOfAClearedScreen() {
        var terminal = Terminal(columns: 30, rows: 6)
        terminal.receive("\u{1B}]133;A\u{7}top line of a long prompt\u{1B}[2J\u{1B}[Hlong output line\r\n% ")
        terminal.resize(columns: 10, rows: 6)
        #expect(screenLines(terminal) == ["long outpu", "t line", "%", "", "", ""])
    }

    @Test func trimsTheOldestCommands() {
        var terminal = Terminal(columns: 20, rows: 5)
        let command = "\u{1B}]133;C;cmdline_url=x\u{7}\u{1B}]133;D;0\u{7}"
        terminal.receive(String(repeating: command, count: 11_000))
        #expect(terminal.commands.count == 11_000)
        terminal.receive(command)
        #expect(terminal.commands.count == 10_000)
        #expect(terminal.removedCommandCount == 1_001)
        #expect(terminal.commands.last?.isFinished == true)
    }
}

private func screenLines(_ terminal: Terminal) -> [String] {
    terminal.screen.map { String($0.map(terminal.character(of:))).trimmingCharacters(in: .whitespaces) }
}

private func scrollbackLines(_ terminal: Terminal) -> [String] {
    terminal.scrollback.map { String($0.map(terminal.character(of:))).trimmingCharacters(in: .whitespaces) }
}

private func text(at position: Terminal.Position?, in terminal: Terminal) -> String {
    guard let position else {
        return "nil"
    }
    let index = position.row - terminal.removedScrollbackCount
    guard index >= 0 else {
        return ""
    }
    let line =
        index < terminal.scrollback.count
        ? terminal.scrollback[index] : terminal.screen[index - terminal.scrollback.count]
    return String(line.dropFirst(position.column).map(terminal.character(of:))).trimmingCharacters(in: .whitespaces)
}
