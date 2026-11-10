import Foundation
import Testing

@testable import TerminalCore

@Suite(.timeLimit(.minutes(1)))
struct ProgramSessionTests {
    static let handled: Set<String> = [
        "C0 08", "C0 0A", "C0 0D", "ESC (B", "ESC =", "ESC >", "ESC M", "CSI P", "CSI ?7l",
        "CSI C", "CSI G", "CSI H", "CSI J", "CSI K", "CSI d", "CSI r", "CSI 4l", "CSI 6n", "CSI >c", "CSI >4m",
        "CSI m", "CSI 0m", "CSI 1m", "CSI 4m", "CSI 7m", "CSI 23m", "CSI 24m", "CSI 27m", "CSI 32m", "CSI 33m",
        "CSI 36m", "CSI 94m", "CSI ?1h", "CSI ?1l", "CSI ?7h", "CSI ?25h", "CSI ?25l", "CSI ?1004h", "CSI ?1004l",
        "CSI ?1049h", "CSI ?1049l", "CSI ?2004h", "CSI ?2004l", "OSC 7", "OSC 10", "OSC 11",
    ]

    static let ignored: Set<String> = [
        "ESC \\", "CSI 0%m", "CSI 22t", "CSI 23t", "CSI 29m", "CSI ?4m", "CSI ?$p", "CSI ?12h", "CSI ?12l",
        "CSI ?1034h",
    ]

    @Test(.enabled(if: isInstalled("/bin/zsh")))
    func loginShell() async throws {
        try await run { session in
            try await session.start()
            try await session.wait { $0.lines[$0.cursor.row] == "%" && $0.cursor.column == 2 }
            await session.send("echo ${HOME:t} ${PWD:t} two\r")
            try await session.wait { $0.lines.contains("home home two") && $0.lines[$0.cursor.row] == "%" }
            let row = await session.cursor.row
            await session.press(.up)
            try await session.wait {
                $0.lines[row] == "% echo ${HOME:t} ${PWD:t} two" && $0.cursor == Terminal.Position(row: row, column: 29)
            }
            await session.send("\u{17}three")
            try await session.wait { $0.lines[row] == "% echo ${HOME:t} ${PWD:t} three" }
            await session.press(.left)
            await session.press(.left)
            await session.send("X\u{5}.\r")
            try await session.wait {
                $0.lines[row + 1] == "home home thrXee." && $0.cursor == Terminal.Position(row: row + 2, column: 2)
            }
            await session.send("exit\r")
            #expect(try await session.exit() == .exit(0))
        }
    }

    @Test(.enabled(if: isInstalled("/usr/bin/vim")))
    func vim() async throws {
        try await run { session in
            try await session.start(["/usr/bin/vim", "notes.txt"])
            try await session.wait {
                $0.lines[23].hasPrefix("\"notes.txt\" [New]") && $0.cursor == Terminal.Position(row: 0, column: 0)
            }
            await session.send("ifirst line\rsecond line\u{1B}")
            try await session.wait {
                $0.lines.prefix(2) == ["first line", "second line"] && !$0.lines[23].contains("INSERT")
                    && $0.cursor == Terminal.Position(row: 1, column: 10)
            }
            await session.send("ggA end\u{1B}")
            try await session.wait {
                $0.lines[0] == "first line end" && !$0.lines[23].contains("INSERT")
                    && $0.cursor == Terminal.Position(row: 0, column: 13)
            }
            await session.send(":wq\r")
            #expect(try await session.exit() == .exit(0))
            await expectNormalScreen(session)
            #expect(
                try String(contentsOf: session.url("work/notes.txt"), encoding: .utf8)
                    == "first line end\nsecond line\n")
        }
    }

    @Test(.enabled(if: isInstalled("/usr/bin/less")))
    func less() async throws {
        try await run { session in
            try session.write((1 ... 200).map { String(format: "line %03d\n", $0) }.joined(), to: "work/lines.txt")
            try await session.start(["/usr/bin/less", "lines.txt"])
            try await session.wait { $0.lines[0] == "line 001" && $0.lines[22] == "line 023" && $0.cursor.row == 23 }
            await session.send(" ")
            try await session.wait { $0.lines[0] == "line 024" && $0.lines[22] == "line 046" }
            await session.send("/line 150\r")
            try await session.wait { $0.lines[0] == "line 150" }
            await session.send("q")
            #expect(try await session.exit() == .exit(0))
            await expectNormalScreen(session)
        }
    }

    @Test(.enabled(if: isInstalled("/usr/bin/man")))
    func man() async throws {
        try await run { session in
            try await session.start(["/usr/bin/man", "ls"])
            try await session.wait {
                $0.lines.contains("NAME") && $0.lines.contains { $0.contains("list directory contents") }
                    && $0.cursor.row == 23
            }
            await session.send("q")
            #expect(try await session.exit() == .exit(0))
            await expectNormalScreen(session)
        }
    }

    @Test(.enabled(if: isInstalled("/usr/bin/top")))
    func top() async throws {
        try await run { session in
            try await session.start(["/usr/bin/top"])
            try await session.wait { $0.lines[0].hasPrefix("Processes:") && $0.lines.contains { $0.hasPrefix("PID") } }
            await session.send("q")
            #expect(try await session.exit() == .exit(0))
            await expectNormalScreen(session)
        }
    }

    @Test(.enabled(if: isInstalled("/usr/bin/nano")))
    func nano() async throws {
        try await run { session in
            try await session.start(["/usr/bin/nano", "notes.txt"])
            try await session.wait {
                $0.lines[0].contains("notes.txt") && $0.cursor == Terminal.Position(row: 2, column: 0)
            }
            await session.send("hello from nano")
            try await session.wait {
                $0.lines[2] == "hello from nano" && $0.cursor == Terminal.Position(row: 2, column: 15)
            }
            await session.send("\u{18}")
            try await session.wait { $0.lines.contains { $0.contains("Save modified buffer") } }
            await session.send("y")
            try await session.wait { $0.lines.contains { $0.contains("File Name to write") } }
            await session.send("\r")
            #expect(try await session.exit() == .exit(0))
            await expectNormalScreen(session)
            #expect(try String(contentsOf: session.url("work/notes.txt"), encoding: .utf8) == "hello from nano\n")
        }
    }

    @Test(.enabled(if: isInstalled("/usr/bin/git")))
    func git() async throws {
        try await run { session in
            let commit = "git -c user.name=Test -c user.email=test@example.invalid commit -qm"
            let commits = "for i in 1 2 3 4 5 6; do seq $i > lines.txt; git add .; \(commit) \"Change $i\"; done"
            try await session.start(
                ["/bin/sh", "-c", "git init -qb main && \(commits) && exec git log -p"],
                environment: ["GIT_CONFIG_NOSYSTEM": "1"]
            )
            try await session.wait {
                $0.lines[23] == ":" && $0.lines[4] == "    Change 6"
                    && $0.cursor == Terminal.Position(row: 23, column: 1)
            }
            #expect(await session.lines[1] == "Author: Test <test@example.invalid>")
            #expect(await session.terminal.screen[0][0].style.foreground == .indexed(3))
            let added = try #require(await session.lines.firstIndex(of: "+6"))
            #expect(await session.terminal.screen[added][0].style.foreground == .indexed(2))
            await session.send("/Change 2\r")
            try await session.wait { $0.lines[0] == "    Change 2" }
            await session.send("q")
            #expect(try await session.exit() == .exit(0))
            #expect(await !session.terminal.isAlternateScreenActive)
            #expect(await session.cursor == Terminal.Position(row: 23, column: 0))
        }
    }

    private func run(_ script: (ProgramSession) async throws -> Void) async throws {
        let session = try ProgramSession()
        do {
            try await script(session)
        } catch {
            await session.close()
            throw error
        }
        await session.close()
        let unknown = await session.controlFunctions.subtracting(Self.handled).subtracting(Self.ignored)
        #expect(unknown.isEmpty, "Not in a list: \(unknown.sorted())")
    }

    private func expectNormalScreen(_ session: ProgramSession, sourceLocation: SourceLocation = #_sourceLocation) async
    {
        #expect(await !session.terminal.isAlternateScreenActive, sourceLocation: sourceLocation)
        #expect(await session.cursor == Terminal.Position(row: 0, column: 0), sourceLocation: sourceLocation)
        #expect(await session.lines == Array(repeating: "", count: 24), sourceLocation: sourceLocation)
    }
}

private func isInstalled(_ path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
}
