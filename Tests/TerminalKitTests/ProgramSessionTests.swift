import Foundation
import Testing

@testable import TerminalCore
@testable import TerminalKit

@Suite(.timeLimit(.minutes(1)))
struct ProgramSessionTests {
    static let handled: Set<String> = [
        "C0 08", "C0 0A", "C0 0D", "ESC (B", "ESC 7", "ESC 8", "ESC =", "ESC >", "ESC M", "CSI P", "CSI ?7l",
        "CSI A", "CSI B", "CSI C", "CSI D", "CSI c", "CSI G", "CSI H", "CSI J", "CSI 2J", "CSI K", "CSI 2K", "CSI d",
        "CSI r", "CSI 4l", "CSI 6n", "CSI >c", "CSI >4m", "CSI >4;0m", "CSI >4;2m", "CSI m", "CSI 0m", "CSI 1m",
        "CSI 2m", "CSI 4m", "CSI 7m", "CSI 22m", "CSI 23m", "CSI 24m", "CSI 27m", "CSI 32m", "CSI 33m", "CSI 36m",
        "CSI 38;2m", "CSI 39m", "CSI 48;2m", "CSI 49m", "CSI 94m", "CSI ?1h", "CSI ?1l", "CSI ?7h", "CSI ?25h",
        "CSI ?25l", "CSI ?1000l", "CSI ?1002l", "CSI ?1003l", "CSI ?1004h", "CSI ?1004l", "CSI ?1006l", "CSI ?1049h",
        "CSI ?1049l", "CSI ?2004h", "CSI ?2004l", "CSI ?2026h", "CSI ?2026l", "OSC 0", "OSC 2", "OSC 7", "OSC 10;?",
        "OSC 11;?", "CSI 22;1t", "CSI 22;2t", "CSI 23;1t", "CSI 23;2t", "CSI ?4m",
    ]

    static let ignored: Set<String> = [
        "ESC \\", "CSI 0%m", "CSI 29m", "CSI ?$p", "CSI ?12h", "CSI ?12l",
        "CSI ?1034h", "C0 0F", "CSI >q", "CSI ?u", "CSI ?1016l", "CSI ?2031h", "CSI ?2031l", "OSC 7501",
    ]

    @Test(.enabled(if: getpwuid(getuid()).map { String(cString: $0.pointee.pw_shell) } == "/bin/zsh"))
    func loginShell() async throws {
        try await run { session in
            try await session.start()
            try await session.wait {
                $0.lines[$0.cursor.row] == "%"
                    && $0.cursor == Terminal.Position(row: $0.lines[0].hasPrefix("Last login:") ? 1 : 0, column: 2)
            }
            let start = await session.cursor.row
            await session.send("echo ${HOME:t} ${PWD:t} two\r")
            try await session.wait {
                $0.lines[start + 1] == "home home two" && $0.lines[start + 2] == "%"
                    && $0.cursor == Terminal.Position(row: start + 2, column: 2)
            }
            let row = start + 2
            await session.press(.up)
            try await session.wait {
                $0.lines[row] == "% echo ${HOME:t} ${PWD:t} two" && $0.cursor == Terminal.Position(row: row, column: 29)
            }
            await session.send("\u{17}three")
            try await session.wait {
                $0.lines[row] == "% echo ${HOME:t} ${PWD:t} three"
                    && $0.cursor == Terminal.Position(row: row, column: 31)
            }
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
            try await session.start([
                "/bin/sh", "-c", "printf '\\033]2;before vim\\007'; exec /usr/bin/vim --cmd 'set title' notes.txt",
            ])
            try await session.wait {
                $0.lines[23].hasPrefix("\"notes.txt\" [New]") && $0.cursor == Terminal.Position(row: 0, column: 0)
                    && $0.terminal.title.contains("notes.txt")
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
            #expect(await session.terminal.title == "before vim")
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
            try await session.wait {
                $0.lines[0] == "line 001" && $0.lines[22] == "line 023"
                    && $0.cursor == Terminal.Position(row: 23, column: 9)
            }
            await session.send(" ")
            try await session.wait {
                $0.lines[0] == "line 024" && $0.lines[22] == "line 046"
                    && $0.cursor == Terminal.Position(row: 23, column: 1)
            }
            await session.send("/line 150\r")
            try await session.wait { $0.lines[0] == "line 150" && $0.cursor == Terminal.Position(row: 23, column: 1) }
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
                    && $0.cursor == Terminal.Position(row: 23, column: 1)
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
            try await session.wait {
                $0.lines[0].hasPrefix("Processes:") && $0.lines.contains { $0.hasPrefix("PID") }
                    && $0.cursor == Terminal.Position(row: 23, column: min($0.lines[23].count, 79))
            }
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
            try await session.wait {
                $0.lines.contains { $0.contains("Save modified buffer") }
                    && $0.cursor == Terminal.Position(row: 21, column: 61)
            }
            await session.send("y")
            try await session.wait {
                $0.lines.contains { $0.contains("File Name to write") }
                    && $0.cursor == Terminal.Position(row: 21, column: 30)
            }
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
            try await session.wait {
                $0.lines[0] == "    Change 2" && $0.cursor == Terminal.Position(row: 23, column: 5)
            }
            await session.send("q")
            #expect(try await session.exit() == .exit(0))
            #expect(await !session.terminal.isAlternateScreenActive)
            #expect(await session.cursor == Terminal.Position(row: 23, column: 0))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TERMINALKIT_CLAUDE_SESSION"] != nil && claudeURL != nil))
    func claudeCode() async throws {
        let folder = URL(filePath: "/tmp/TerminalKitClaudeSession")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var configuration = TerminalSession.Configuration(
            executableURL: try #require(claudeURL),
            arguments: [
                "--model", "haiku", "--permission-mode", "default", "--safe-mode", "--strict-mcp-config", "--no-chrome",
                "--settings", #"{"spinnerTipsEnabled":false}"#,
            ],
            currentDirectoryURL: folder
        )
        configuration.environment["DISABLE_AUTOUPDATER"] = "1"
        configuration.environment["IS_DEMO"] = "1"
        configuration.environment["TZ"] = "UTC"
        let session = try await run { session in
            try await session.start(configuration)
            try await session.wait(timeout: .seconds(30)) {
                $0.lines.contains("  Yes, I trust this folder") || $0.isReady
            }
            if await session.lines.contains("  Yes, I trust this folder") {
                await session.press(.down)
                try await session.wait { $0.lines.contains("❯ Yes, I trust this folder") }
                await session.send("\r")
            }
            try await session.wait(timeout: .seconds(30)) { $0.isReady }

            try await session.submit("Reply with the single word pineapple and nothing else.")
            try await session.wait(timeout: .seconds(60)) {
                $0.isReady && $0.lines.contains { $0.lowercased() == "⏺ pineapple" }
            }

            try await session.submit("Run in Bash: echo tk-$((6*7))")
            try await session.wait(timeout: .seconds(60)) {
                $0.isReady && $0.lines.contains("⏺ Bash(echo tk-$((6*7)))")
                    && $0.lines.contains { $0.contains("⎿") && $0.hasSuffix("tk-42") }
            }

            try await session.submit("Create the file note.txt with the content tk-file. Use the Write tool.")
            try await session.wait(timeout: .seconds(60)) {
                $0.lines.contains { $0.contains("Do you want to create note.txt?") }
                    && $0.lines.contains { $0.trimmingCharacters(in: .whitespaces) == "❯ 1. Yes" }
            }
            await session.send("\r")
            try await session.wait(timeout: .seconds(60)) {
                $0.isReady && $0.lines.contains { $0.hasPrefix("⏺ Write(note.txt)") }
            }
            try #require(
                try String(contentsOf: folder.appending(path: "note.txt"), encoding: .utf8)
                    .trimmingCharacters(in: .newlines) == "tk-file")

            await session.send("/")
            try await session.wait { $0.input == ["❯ /"] && $0.menuRows.count >= 5 }
            await session.send("\u{1B}")
            try await session.wait { $0.input == ["❯ /"] && $0.menuRows.isEmpty }
            await session.send("\u{7F}")
            try await session.wait { $0.isReady && $0.menuRows.isEmpty }

            await session.send("alpha")
            try await session.wait { $0.input == ["❯ alpha"] }
            try await session.pressShiftReturn()
            await session.send("beta")
            try await session.wait { $0.input == ["❯ alpha", "  beta"] }
            try #require(await session.lines.filter { $0.contains("alpha") }.count == 1)
            await session.send("\u{3}")
            try await session.wait { $0.isReady && !$0.lines.contains { $0.contains("again to exit") } }

            await session.paste("日本語 paste\n🇮🇹 1️⃣ 👨‍👩‍👧 👍🏽 end")
            try await session.wait {
                $0.input == ["❯ 日本語 paste", "  🇮🇹 1️⃣ 👨‍👩‍👧 👍🏽 end"] && $0.cursor.column == 17
                    && $0.lines[$0.cursor.row].hasSuffix(" end")
            }
            await session.send("\u{3}")
            try await session.wait { $0.isReady && !$0.lines.contains { $0.contains("again to exit") } }

            try #require(await session.scrollbackLines.contains { $0.lowercased() == "⏺ pineapple" })

            for (columns, rows) in [(100, 30), (60, 20), (80, 24)] {
                await session.resize(columns: columns, rows: rows)
                try await session.wait {
                    $0.isReady && $0.lines.filter { $0.contains("? for shortcuts") }.count == 1
                        && $0.lines.filter { $0.lowercased() == "⏺ pineapple" }.count <= 1
                }
            }

            try await session.submit("/exit")
            try #require(try await session.exit() == .exit(0))
            try #require(await session.ruleRows.count <= 2)
            try #require(await session.lines.contains("Resume this session with:"))
            try #require(await session.controlFunctions.isSuperset(of: ["CSI ?2026h", "CSI ?2026l"]))
        }
        if ProcessInfo.processInfo.environment["TERMINALKIT_CLAUDE_SESSION"] == "record" {
            try await record(session)
        }
    }

    @Test func claudeCodeRecording() throws {
        let events = try JSONDecoder().decode([ProgramSession.Event].self, from: Data(contentsOf: recordingURL()))
        var whole = ProgramSession.newTerminal()
        var split = whole
        var output: [UInt8] = []
        for event in events {
            if let text = event.output?.joined() {
                let bytes = unescaped(text)
                output += bytes
                _ = whole.receive(bytes)
                for byte in bytes {
                    _ = split.receive([byte])
                }
            }
            if let columns = event.columns, let rows = event.rows {
                whole.resize(columns: columns, rows: rows)
                split.resize(columns: columns, rows: rows)
            }
            if event.screen != nil {
                #expect(ProgramSession.checkpoint(whole) == event)
                #expect(split.screen == whole.screen && split.cursor == whole.cursor)
            }
        }
        #expect(events.count { $0.screen != nil } > 10)
        let unknown = ProgramSession.controlFunctions(in: output).subtracting(Self.handled).subtracting(Self.ignored)
        #expect(unknown.isEmpty, "Not in a list: \(unknown.sorted())")
    }

    @Test func claudeCodeRecordingHasNoPrivateData() throws {
        let text = try String(contentsOf: recordingURL(), encoding: .utf8)
        for word in ["/Users/", "sk-ant", NSHomeDirectory(), NSUserName(), NSFullUserName()] where !word.isEmpty {
            #expect(!text.contains(word))
        }
        #expect(text.firstMatch(of: /[\w.%+-]+@[\w-]+\.[\w.-]+/) == nil)
        let uuids = text.matches(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/)
        #expect(uuids.allSatisfy { $0.output == uuidPlaceholder })
        #expect(text.firstMatch(of: /[A-Za-z0-9_]{32,}/) == nil)
        #expect(text.firstMatch(of: planName) == nil)
        #expect(!text.contains("% of your") && !text.contains("Tip:"))
    }

    private func record(_ session: ProgramSession) async throws {
        let output = await session.output
        var text = try #require(String(validating: output, as: UTF8.self))
        for (word, placeholder) in [
            (NSHomeDirectory(), "/home/user/"), (NSFullUserName(), "Person "), (NSUserName(), "user"),
        ]
        where !word.isEmpty {
            text = text.replacing(
                word, with: String(repeating: placeholder, count: word.utf8.count).prefix(word.utf8.count))
        }
        text = text.replacing(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) { _ in
            uuidPlaceholder
        }
        text = text.replacing(planName) {
            $0.output.0.dropLast($0.output.1.count) + String(repeating: " ", count: $0.output.1.count)
        }
        let bytes = Array(text.utf8)
        try #require(bytes.count == output.count)
        var live = ProgramSession.newTerminal()
        var terminal = live
        var events: [ProgramSession.Event] = []
        var start = 0
        for (offset, event) in await session.events {
            if offset > start {
                _ = live.receive(Array(output[start ..< offset]))
                _ = terminal.receive(Array(bytes[start ..< offset]))
                events.append(.init(output: escaped(bytes[start ..< offset]).split(separator: "\n").map(String.init)))
                start = offset
            }
            if let columns = event.columns, let rows = event.rows {
                live.resize(columns: columns, rows: rows)
                terminal.resize(columns: columns, rows: rows)
                events.append(event)
            } else {
                try #require(ProgramSession.checkpoint(live) == event)
                events.append(ProgramSession.checkpoint(terminal))
            }
        }
        try #require(unescaped(events.compactMap { $0.output?.joined() }.joined()) == Array(bytes[..<start]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(events)
            .write(
                to: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Recordings/claude-code.json"))
    }

    private func recordingURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "claude-code", withExtension: "json", subdirectory: "Recordings"))
    }

    private func escaped(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self).unicodeScalars
            .map { scalar in
                scalar.value >= 0xA0 || (0x20 ..< 0x7F).contains(scalar.value) && scalar != "\\"
                    ? String(scalar) : String(scalar).utf8.map { String(format: "\\x%02X", $0) }.joined()
            }
            .joined()
            .replacing("\\x0A", with: "\\x0A\n")
    }

    private func unescaped(_ text: String) -> [UInt8] {
        let pieces = text.components(separatedBy: "\\x")
        return Array(pieces[0].utf8)
            + pieces.dropFirst().flatMap { [UInt8($0.prefix(2), radix: 16) ?? 0] + Array($0.utf8.dropFirst(2)) }
    }

    @discardableResult
    private func run(_ script: (ProgramSession) async throws -> Void) async throws -> ProgramSession {
        let session = try ProgramSession()
        do {
            try await script(session)
        } catch {
            await session.close()
            throw error
        }
        await session.close()
        let unknown = await session.controlFunctions.subtracting(Self.handled).subtracting(Self.ignored)
        try #require(unknown.isEmpty, "Not in a list: \(unknown.sorted())")
        return session
    }

    private func expectNormalScreen(_ session: ProgramSession, sourceLocation: SourceLocation = #_sourceLocation) async
    {
        #expect(await !session.terminal.isAlternateScreenActive, sourceLocation: sourceLocation)
        #expect(await session.cursor == Terminal.Position(row: 0, column: 0), sourceLocation: sourceLocation)
        #expect(await session.lines == Array(repeating: "", count: 24), sourceLocation: sourceLocation)
    }
}

private let claudeURL =
    ((ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    + ["/opt/homebrew/bin", "/usr/local/bin"] + [".local/bin", ".claude/local"].map { NSHomeDirectory() + "/" + $0 })
    .map { URL(filePath: $0).appending(path: "claude") }
    .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }

extension ProgramSession {
    fileprivate var ruleRows: [Int] {
        lines.indices.filter { !lines[$0].isEmpty && lines[$0].allSatisfy { $0 == "─" } }
    }

    fileprivate var input: [String]? {
        let rules = ruleRows
        guard rules.count == 2, rules.allSatisfy({ lines[$0].count == terminal.columns }) else {
            return nil
        }
        return lines[rules[0] + 1 ..< rules[1]]
            .map { String($0.replacing("\u{A0}", with: " ").reversed().drop { $0 == " " }.reversed()) }
    }

    fileprivate var isReady: Bool {
        input?.count == 1 && input?[0].hasPrefix("❯") == true && lines.contains { $0.contains("? for shortcuts") }
    }

    fileprivate var menuRows: [String] {
        lines.filter { $0.hasPrefix("    /") || $0.hasPrefix("  ❯ /") }
    }

    fileprivate func submit(_ text: String) async throws {
        send(text)
        try await wait { $0.input == ["❯ " + text] }
        send("\r")
    }
}

private let uuidPlaceholder = "00000000-0000-0000-0000-000000000000"

private nonisolated(unsafe) let planName = /Claude(?: |\u{1B}\[\d+G)(Max|Pro|Team|Enterprise)/

private func isInstalled(_ path: String) -> Bool {
    FileManager.default.isExecutableFile(atPath: path)
}
