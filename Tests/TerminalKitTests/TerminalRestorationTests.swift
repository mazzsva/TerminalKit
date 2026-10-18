import AppKit
import Foundation
import TerminalCore
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
final class TerminalRestorationTests {
    enum FolderChange: CaseIterable, Sendable {
        case deleted
        case notSearchable
        case replacedByAFile
    }

    private nonisolated static let shells = ["/bin/zsh", "/bin/bash"]

    private static let scenario = [
        "echo ok",
        "false",
        #"printf '\e[31mred\e[m \e[1;38;5;208mbold\e[m \e[38;2;1;2;3mrgb\e[m\n'"#,
        #"printf '\346\227\245\346\234\254 \360\237\221\215 e\314\201 wide\n'"#,
        #"printf '%0200d\n%079d\346\227\245x\n' 0 0"#,
        "seq 1 40",
        "cd 'sub dir é'",
        "echo here",
    ]

    private let home: URL
    private let folder: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TerminalKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = try #require(realpath(directory.path(percentEncoded: false), nil))
        defer { free(path) }
        home = URL(filePath: String(cString: path))
        folder = home.appending(path: "sub dir é")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("HISTFILE=/dev/null\nSAVEHIST=0\nPS1='zsh%# '\n", to: ".zshrc")
        try write("HISTFILE=/dev/null\nPS1='bash$ '\n", to: ".bash_profile")
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    @Test(arguments: shells)
    func restoresTheSessionOfAShell(shell: String) async throws {
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        for command in Self.scenario {
            await session.run(command, prompt: prompt)
        }
        #expect(session.commands.map(\.exitStatus) == [0, 1, 0, 0, 0, 0, 0, 0])
        #expect(session.commands.map(\.text) == Self.scenario)
        let state = session.restorationState
        let saved = session.snapshot
        session.terminate()
        await session.waitForExit()

        let decoded = try JSONDecoder().decode(TerminalSession.RestorationState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = format
            let decoded = try PropertyListDecoder()
                .decode(
                    TerminalSession.RestorationState.self, from: encoder.encode(state))
            #expect(decoded.terminal == state.terminal, "\(format)")
            #expect(decoded.commands.map(\.text) == state.commands.map(\.text), "\(format)")
            #expect(format == .xml || decoded == state)
        }

        #expect(saved.last?.text == prompt.trimmed)
        let expected = Array(saved.dropLast())
        let restored = TerminalSession(configuration: configuration(shell), restoring: decoded)
        #expect(restored.state == .idle)
        #expect(restored.snapshot == expected)
        #expect(restored.contentLines.last == "here")
        #expect(restored.terminal.scrollback.count > 0)
        #expect(restored.commands == session.commands)
        #expect(restored.currentDirectory == session.currentDirectory)
        #expect(restored.currentDirectory?.path(percentEncoded: false) == folder.path(percentEncoded: false))
        #expect(restored.promptLines == session.commands.map { prompt + ($0.text ?? "") })
        #expect(restored.restorationState.terminal == decoded.terminal)
        #expect(restored.restorationState.commands == decoded.commands)

        try restored.start()
        await restored.waitForPrompt(prompt)
        #expect(Array(restored.snapshot.prefix(expected.count)) == expected)
        #expect(restored.snapshot.count == expected.count + 1)
        await restored.run("pwd", prompt: prompt)
        #expect(restored.logicalLines.contains(folder.path(percentEncoded: false)))
        #expect(restored.commands.map(\.id) == Array(0 ... Self.scenario.count))
        #expect(Array(restored.commands.prefix(Self.scenario.count)) == session.commands)
        #expect(restored.commands.last?.text == "pwd")
        #expect(restored.commands.last?.exitStatus == 0)
        #expect(restored.commands.last?.directory?.path(percentEncoded: false) == folder.path(percentEncoded: false))
        #expect(restored.promptLines == restored.commands.map { prompt + ($0.text ?? "") })
        #expect(Array(restored.snapshot.prefix(expected.count)) == expected)

        let secondState = try JSONDecoder()
            .decode(
                TerminalSession.RestorationState.self, from: JSONEncoder().encode(restored.restorationState))
        let secondSaved = restored.snapshot
        restored.terminate()
        await restored.waitForExit()
        let again = TerminalSession(configuration: configuration(shell), restoring: secondState)
        #expect(again.snapshot == Array(secondSaved.dropLast()))
        #expect(again.commands == restored.commands)
        #expect(again.contentLines.filter { $0 == "ok" }.count == 1)
        #expect(again.contentLines.filter { $0 == "here" }.count == 1)
        #expect(again.logicalLines.filter { $0 == folder.path(percentEncoded: false) }.count == 1)
        #expect(again.contentLines.filter { $0 == prompt.trimmed }.isEmpty)
        try again.start()
        await again.waitForPrompt(prompt)
        await again.run("echo again", prompt: prompt)
        #expect(again.commands.map(\.id) == Array(0 ... Self.scenario.count + 1))
        #expect(again.commands.map(\.text) == Self.scenario + ["pwd", "echo again"])
        #expect(again.promptLines == again.commands.map { prompt + ($0.text ?? "") })
        #expect(Array(again.snapshot.prefix(secondSaved.count - 1)) == Array(secondSaved.dropLast()))
        again.terminate()
        await again.waitForExit()
    }

    @Test(arguments: shells)
    func finishesARunningCommand(shell: String) async throws {
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        await session.run("echo before", prompt: prompt)
        session.send("sleep 30\r")
        await session.waitUntil { session.commands.count == 2 }
        let running = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()
        let terminated = try roundTrip(session.restorationState)

        for (label, state) in [("running", running), ("terminated", terminated)] {
            let restored = TerminalSession(configuration: configuration(shell), restoring: state)
            #expect(restored.contentLines.last == prompt + "sleep 30", "\(label)")
            #expect(restored.commands.map(\.text) == ["echo before", "sleep 30"], "\(label)")
            #expect(restored.commands.last?.exitStatus == nil, "\(label)")
            #expect(restored.commands.last?.endDate != nil, "\(label)")
            #expect(restored.terminal.commands.allSatisfy { $0.isFinished }, "\(label)")
            try restored.start()
            await restored.waitForPrompt(prompt)
            await restored.run("echo after", prompt: prompt)
            #expect(restored.commands.map(\.id) == [0, 1, 2], "\(label)")
            #expect(restored.commands[1].exitStatus == nil, "\(label)")
            #expect(restored.commands[1].endDate != nil, "\(label)")
            #expect(restored.promptLines == restored.commands.map { prompt + ($0.text ?? "") }, "\(label)")
            restored.terminate()
            await restored.waitForExit()
        }
    }

    @Test(arguments: shells)
    func restoresTheMainScreen(shell: String) async throws {
        let prompt = prompt(of: shell)
        let command = #"printf '\033[?1049hFULL SCREEN'; sleep 30"#
        let session = try await startedSession(shell)
        await session.run("echo before", prompt: prompt)
        session.send(command + "\r")
        await session.waitUntil { session.terminal.isAlternateScreenActive && session.allLines.contains("FULL SCREEN") }
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()

        let restored = TerminalSession(configuration: configuration(shell), restoring: state)
        #expect(!restored.terminal.isAlternateScreenActive)
        #expect(!restored.allLines.contains("FULL SCREEN"))
        #expect(restored.contentLines == [prompt + "echo before", "before", prompt + command])
        #expect(restored.commands.last?.exitStatus == nil)
        #expect(restored.commands.last?.endDate != nil)
        try restored.start()
        await restored.waitForPrompt(prompt)
        await restored.run("echo after", prompt: prompt)
        #expect(
            restored.contentLines == [
                prompt + "echo before", "before", prompt + command, prompt + "echo after", "after", prompt.trimmed,
            ])
        #expect(restored.promptLines == restored.commands.map { prompt + ($0.text ?? "") })
        restored.terminate()
        await restored.waitForExit()
    }

    @Test(arguments: shells, FolderChange.allCases)
    func startsInTheFolderOfTheConfiguration(shell: String, change: FolderChange) async throws {
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        await session.run("cd 'sub dir é'", prompt: prompt)
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()
        switch change {
        case .deleted:
            try FileManager.default.removeItem(at: folder)
        case .notSearchable:
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: folder.path(percentEncoded: false))
        case .replacedByAFile:
            try FileManager.default.removeItem(at: folder)
            try Data().write(to: folder)
        }
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))
        }

        let restored = TerminalSession(configuration: configuration(shell), restoring: state)
        try restored.start()
        await restored.waitForPrompt(prompt)
        await restored.run("pwd", prompt: prompt)
        #expect(restored.logicalLines.contains(home.path(percentEncoded: false)))
        #expect(restored.commands.last?.directory?.path(percentEncoded: false) == home.path(percentEncoded: false))
        #expect(restored.currentDirectory?.path(percentEncoded: false) == home.path(percentEncoded: false))
        restored.terminate()
        await restored.waitForExit()
    }

    @Test(arguments: shells)
    func dropsTheTypedTextOfThePrompt(shell: String) async throws {
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        await session.run("echo one", prompt: prompt)
        session.send("echo typed")
        await session.waitUntil { session.contentLines.last == prompt + "echo typed" }
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()

        let restored = TerminalSession(configuration: configuration(shell), restoring: state)
        #expect(restored.contentLines == [prompt + "echo one", "one"])
        try restored.start()
        await restored.waitForPrompt(prompt)
        #expect(restored.contentLines == [prompt + "echo one", "one", prompt.trimmed])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test(arguments: shells)
    func dropsAllLinesOfAPrompt(shell: String) async throws {
        try write("HISTFILE=/dev/null\nSAVEHIST=0\nPS1=$'top line\\nzsh%# '\n", to: ".zshrc")
        try write("HISTFILE=/dev/null\nPS1='top line\\nbash$ '\n", to: ".bash_profile")
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        await session.run("echo one", prompt: prompt)
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()

        let restored = TerminalSession(configuration: configuration(shell), restoring: state)
        #expect(restored.contentLines == ["top line", prompt + "echo one", "one"])
        #expect(restored.promptLines == ["top line"])
        try restored.start()
        await restored.waitForPrompt(prompt)
        await restored.run("echo two", prompt: prompt)
        #expect(
            restored.contentLines == [
                "top line", prompt + "echo one", "one", "top line", prompt + "echo two", "two", "top line",
                prompt.trimmed,
            ]
        )
        #expect(restored.promptLines == ["top line", "top line"])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test(arguments: shells)
    func restoresAnExitedSession(shell: String) async throws {
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        await session.run("echo bye", prompt: prompt)
        session.send("exit\r")
        await session.waitForExit()
        let state = try roundTrip(session.restorationState)

        let restored = TerminalSession(configuration: configuration(shell), restoring: state)
        #expect(restored.state == .idle)
        #expect(
            restored.contentLines == [prompt + "echo bye", "bye", prompt + "exit"]
                + (shell == "/bin/bash" ? ["exit"] : []))
        #expect(restored.commands.map(\.text) == ["echo bye", "exit"])
        #expect(restored.commands.map(\.exitStatus) == [0, nil])
        #expect(restored.commands.allSatisfy { $0.endDate != nil })
        try restored.start()
        await restored.waitForPrompt(prompt)
        await restored.run("echo back", prompt: prompt)
        #expect(restored.commands.map(\.id) == [0, 1, 2])
        #expect(restored.contentLines.suffix(3) == [prompt + "echo back", "back", prompt.trimmed])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test func restoresASessionWithoutTheIntegration() async throws {
        let session = try await startedSession("/bin/zsh", usesShellIntegration: false)
        session.send("echo plain\r")
        await session.waitUntil { session.contentLines == ["zsh% echo plain", "plain", "zsh%"] }
        let saved = session.snapshot
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()

        let restored = TerminalSession(
            configuration: configuration("/bin/zsh", usesShellIntegration: false), restoring: state)
        #expect(restored.snapshot == saved)
        #expect(restored.commands.isEmpty)
        #expect(restored.currentDirectory == nil)
        try restored.start()
        await restored.waitUntil { restored.contentLines.count == 4 }
        #expect(restored.contentLines == ["zsh% echo plain", "plain", "zsh%", "zsh%"])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test func restoresAScript() async throws {
        let configuration = TerminalSession.Configuration(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", #"printf 'hello\n\033[32mgreen\033[m\n'"#],
            environment: environment,
            currentDirectoryURL: home
        )
        let session = TerminalSession(configuration: configuration)
        try session.start()
        await session.waitForExit()
        let saved = session.snapshot
        let state = try roundTrip(session.restorationState)

        let restored = TerminalSession(configuration: configuration, restoring: state)
        #expect(restored.state == .idle)
        #expect(restored.snapshot == saved)
        #expect(restored.contentLines == ["hello", "green"])
        try restored.start()
        await restored.waitForExit()
        #expect(restored.contentLines == ["hello", "green", "hello", "green"])
    }

    @Test(arguments: [300.0, 1100.0])
    func reflowsInAView(width: Double) async throws {
        let prompt = "zsh% "
        let commands = [#"printf '%0200d\n' 0"#, "seq 1 30", "seq 31 60", "seq 61 90"]
        let session = try await startedSession("/bin/zsh")
        for command in commands {
            await session.run(command, prompt: prompt)
        }
        let state = try roundTrip(session.restorationState)
        let saved = Array(session.contentLines.dropLast())
        session.terminate()
        await session.waitForExit()

        let restored = TerminalSession(configuration: configuration("/bin/zsh"), restoring: state)
        let scrollView = TerminalScrollView(session: restored)
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        let columns = restored.terminal.columns
        #expect(columns != 80)
        let zeros = restored.contentLines.filter { !$0.isEmpty && $0.allSatisfy { $0 == "0" } }
        #expect(zeros.joined().count == 200)
        #expect(zeros.count == (200 + columns - 1) / columns)
        #expect(restored.promptLines == commands.map { prompt + $0 })
        #expect(scrollView.contentView.bounds.maxY == view.frame.height)
        view.scrollToBottom()
        scrollView.layoutSubtreeIfNeeded()

        var tops: [String] = []
        for _ in 0 ..< 5 {
            view.keyDown(with: try commandKey(NSUpArrowFunctionKey))
            tops.append(topLine(of: scrollView))
        }
        #expect(
            tops == ["zsh% seq 61 90", "zsh% seq 31 60", "zsh% seq 1 30", prompt + commands[0], prompt + commands[0]])
        restored.reveal(restored.commands[2])
        scrollView.layoutSubtreeIfNeeded()
        #expect(topLine(of: scrollView) == "zsh% seq 31 60")

        let resized = TerminalSession(
            configuration: configuration("/bin/zsh"), restoring: try roundTrip(restored.restorationState))
        #expect(resized.terminal.columns == columns)
        resized.resize(columns: 80, rows: 24)
        #expect(resized.snapshot.map(\.text) == saved)
        #expect(resized.promptLines == commands.map { prompt + $0 })

        try restored.start()
        await restored.waitForPrompt(prompt)
        await restored.run("seq 91 120", prompt: prompt)
        scrollView.layoutSubtreeIfNeeded()
        view.scrollToBottom()
        scrollView.layoutSubtreeIfNeeded()
        tops = []
        for _ in 0 ..< 6 {
            view.keyDown(with: try commandKey(NSUpArrowFunctionKey))
            tops.append(topLine(of: scrollView))
        }
        #expect(
            tops == [
                "zsh% seq 91 120", "zsh% seq 61 90", "zsh% seq 31 60", "zsh% seq 1 30", prompt + commands[0],
                prompt + commands[0],
            ]
        )
        #expect(restored.promptLines == (commands + ["seq 91 120"]).map { prompt + $0 })
        restored.terminate()
        await restored.waitForExit()
    }

    @Test(arguments: [(0, 1_000_000), (5_000, 0)])
    func restoresADamagedState(columns: Int, rows: Int) async throws {
        let session = try await startedSession("/bin/zsh")
        await session.run("echo one", prompt: "zsh% ")
        await session.run("echo two", prompt: "zsh% ")
        let data = try JSONEncoder().encode(session.restorationState)
        session.terminate()
        await session.waitForExit()

        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var terminal = try #require(root["terminal"] as? [String: Any])
        terminal["columns"] = columns
        terminal["rows"] = rows
        terminal["removedCommandCount"] = -3
        terminal["currentDirectory"] = "https://example.com/folder"
        var commands = try #require(terminal["commands"] as? [[String: Any]])
        commands[0]["prompt"] = ["row": -10, "column": -4]
        commands[0]["output"] = ["row": 1_000_000, "column": 1_000_000]
        commands[1]["prompt"] = ["row": 1, "column": 9_999]
        commands[1]["isFinished"] = false
        terminal["commands"] = commands
        root["terminal"] = terminal
        root["commands"] = []
        let state = try JSONDecoder()
            .decode(
                TerminalSession.RestorationState.self, from: JSONSerialization.data(withJSONObject: root))

        let restored = TerminalSession(configuration: configuration("/bin/zsh"), restoring: state)
        #expect(restored.terminal.columns == min(max(columns, 1), 1_000))
        #expect(restored.terminal.rows == min(max(rows, 1), 1_000))
        #expect(restored.commands.map(\.id) == [0, 1])
        #expect(restored.commands.allSatisfy { $0.endDate != nil })
        #expect(restored.currentDirectory == nil)
        let scrollView = TerminalScrollView(session: restored)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        for _ in 0 ..< 3 {
            scrollView.terminalView.keyDown(with: try commandKey(NSUpArrowFunctionKey))
        }
        restored.reveal(restored.commands[0])
        restored.reveal(restored.commands[1])
        scrollView.layoutSubtreeIfNeeded()
        try restored.start()
        await restored.waitForPrompt("zsh% ")
        await restored.run("echo three", prompt: "zsh% ")
        #expect(restored.commands.map(\.id) == [0, 1, 2])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test func restoresTheOldestLinesThatAreLeft() async throws {
        let session = try await startedSession("/bin/zsh")
        await session.run("seq 1 12000", prompt: "zsh% ")
        await session.run("echo done", prompt: "zsh% ")
        #expect(session.terminal.removedScrollbackCount > 0)
        let saved = Array(session.snapshot.dropLast())
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()

        let restored = TerminalSession(configuration: configuration("/bin/zsh"), restoring: state)
        let lines = restored.snapshot
        #expect(lines.count <= saved.count)
        #expect(Array(saved.suffix(lines.count)) == lines)
        #expect(restored.contentLines.last == "done")
        #expect(restored.promptLines.last == "zsh% echo done")
        #expect(restored.promptLines.count == 2)
        #expect(restored.promptLines.first == .some(nil) || restored.promptLines.first == "zsh% seq 1 12000")
        try restored.start()
        await restored.waitForPrompt("zsh% ")
        await restored.run("echo after", prompt: "zsh% ")
        #expect(restored.promptLines.suffix(2) == ["zsh% echo done", "zsh% echo after"])
        #expect(restored.commands.map(\.id) == [0, 1, 2])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test func keepsTheIDsOfTrimmedCommands() async throws {
        let configuration = TerminalSession.Configuration(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: [
                "-c",
                """
                i=0
                while [ $i -lt 11001 ]; do
                    printf '\\033]133;A\\007$ %d\\r\\n\\033]133;C\\007\\033]133;D;0\\007' $i
                    i=$((i + 1))
                done
                """,
            ],
            environment: environment,
            currentDirectoryURL: home
        )
        let session = TerminalSession(configuration: configuration)
        try session.start()
        await session.waitForExit()
        #expect(session.commands.first?.id == 1_001)
        let state = try roundTrip(session.restorationState)

        let restored = TerminalSession(configuration: configuration, restoring: state)
        #expect(restored.commands == session.commands)
        #expect(restored.terminal.removedCommandCount == 1_001)
        #expect(restored.promptLines.last == "$ 11000")
        try restored.start()
        await restored.waitForExit()
        #expect(restored.commands.count == 10_991)
        #expect(restored.commands.first?.id == 11_011)
        #expect(restored.commands.last?.id == 22_001)
        #expect(restored.commands.map(\.id) == Array(11_011 ... 22_001))
        #expect(restored.commands.last?.text == nil)
    }

    @Test(arguments: shells)
    func keepsTheOutputAfterThePrompt(shell: String) async throws {
        let prompt = prompt(of: shell)
        let session = try await startedSession(shell)
        session.send("(sleep 0.5; echo late; sleep 5) &\r")
        await session.waitUntil { session.contentLines.last == prompt + "late" }
        let state = try roundTrip(session.restorationState)
        session.terminate()
        await session.waitForExit()
        let restored = TerminalSession(configuration: configuration(shell), restoring: state)
        #expect(restored.contentLines.contains { $0.hasSuffix("late") }, "\(restored.contentLines)")
    }

    @Test func restoresASessionThatNeverStarted() async throws {
        let state = try roundTrip(TerminalSession(configuration: configuration("/bin/zsh")).restorationState)
        let restored = TerminalSession(configuration: configuration("/bin/zsh"), restoring: state)
        #expect(restored.snapshot.isEmpty)
        #expect(restored.commands.isEmpty)
        #expect(restored.currentDirectory == nil)
        try restored.start()
        await restored.waitForPrompt("zsh% ")
        await restored.run("pwd", prompt: "zsh% ")
        #expect(restored.logicalLines == ["zsh% pwd", home.path(percentEncoded: false), "zsh%"])
        #expect(restored.commands.map(\.id) == [0])
        restored.terminate()
        await restored.waitForExit()
    }

    @Test func restoresTheLinks() async throws {
        let configuration = TerminalSession.Configuration(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", #"printf '\033]8;;https://example.com/a\033\\link\033]8;;\033\\ plain\n'"#],
            environment: environment,
            currentDirectoryURL: home
        )
        let session = TerminalSession(configuration: configuration)
        try session.start()
        await session.waitForExit()
        let state = try roundTrip(session.restorationState)

        let restored = TerminalSession(configuration: configuration, restoring: state)
        #expect(restored.contentLines == ["link plain"])
        let terminal = restored.terminal
        let line = try #require(terminal.scrollback.first ?? terminal.screen.first)
        #expect(line.prefix(4).allSatisfy { terminal.links.uri(of: $0.style.link) == "https://example.com/a" })
        #expect(line[4 ..< 10].allSatisfy { $0.style.link == 0 })
    }

    private var environment: [String: String] {
        let path = home.path(percentEncoded: false)
        return [
            "HOME": path, "ZDOTDIR": path, "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "SHELL_SESSIONS_DISABLE": "1",
            "BASH_SILENCE_DEPRECATION_WARNING": "1",
        ]
    }

    private func configuration(_ shell: String, usesShellIntegration: Bool = true) -> TerminalSession.Configuration {
        .init(
            executableURL: URL(filePath: shell),
            arguments: ["-l"],
            environment: environment,
            currentDirectoryURL: home,
            usesShellIntegration: usesShellIntegration
        )
    }

    private func startedSession(_ shell: String, usesShellIntegration: Bool = true) async throws -> TerminalSession {
        let session = TerminalSession(configuration: configuration(shell, usesShellIntegration: usesShellIntegration))
        try session.start()
        await session.waitForPrompt(prompt(of: shell))
        return session
    }

    private func prompt(of shell: String) -> String {
        shell.hasSuffix("zsh") ? "zsh% " : "bash$ "
    }

    private func roundTrip(_ state: TerminalSession.RestorationState) throws -> TerminalSession.RestorationState {
        try JSONDecoder().decode(TerminalSession.RestorationState.self, from: JSONEncoder().encode(state))
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: home.appending(path: path))
    }
}

private struct LineSnapshot: Equatable {
    struct Cell: Equatable {
        var character: Character
        var style: Terminal.Style
        var width: UInt8
    }

    var cells: [Cell]
    var isWrapped: Bool

    var rawText: String {
        String(cells.filter { $0.width > 0 && $0.character != "\u{0}" }.map(\.character))
    }

    var text: String {
        rawText.trimmingCharacters(in: .whitespaces)
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }
}

extension TerminalSession {
    fileprivate var snapshot: [LineSnapshot] {
        let terminal = terminal
        var lines = (terminal.scrollback + terminal.screen)
            .map { line in
                let end = (line.lastIndex { !$0.isBlank } ?? -1) + 1
                return LineSnapshot(
                    cells: line[0 ..< end]
                        .map { .init(character: terminal.character(of: $0), style: $0.style, width: $0.width) },
                    isWrapped: line.isWrapped
                )
            }
        while lines.last?.cells.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    fileprivate var logicalLines: [String] {
        var lines: [String] = []
        var continues = false
        for line in snapshot {
            if continues {
                lines[lines.count - 1] += line.rawText
            } else {
                lines.append(line.rawText)
            }
            continues = line.isWrapped
        }
        return lines.map(\.trimmed)
    }

    fileprivate var allLines: [String] {
        let terminal = terminal
        return (terminal.scrollback + terminal.screen).map(terminal.text(of:))
    }

    fileprivate var contentLines: [String] {
        snapshot.map(\.text)
    }

    fileprivate var promptLines: [String?] {
        let terminal = terminal
        let lines = terminal.scrollback + terminal.screen
        return terminal.commands.map { command in
            guard let row = command.prompt.map({ $0.row - terminal.removedScrollbackCount }),
                lines.indices.contains(row)
            else {
                return nil
            }
            return terminal.text(of: lines[row])
        }
    }

    fileprivate func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for await isMet in Observations({ condition() }) where isMet {
            return
        }
    }

    fileprivate func waitForPrompt(_ prompt: String) async {
        await waitUntil { self.contentLines.last == prompt.trimmed }
    }

    fileprivate func run(_ command: String, prompt: String) async {
        let count = commands.count
        send(command + "\r")
        await waitUntil {
            self.commands.count == count + 1 && self.commands.last?.endDate != nil
                && self.contentLines.last == prompt.trimmed
        }
    }
}

extension Terminal {
    fileprivate func text(of line: Line) -> String {
        String(line.filter { $0.width > 0 && $0 != .padding }.map(character(of:))).trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
private func commandKey(_ key: Int) throws -> NSEvent {
    try keyDown(key, modifierFlags: [.command, .numericPad, .function])
}

@MainActor
private func topLine(of scrollView: TerminalScrollView) -> String {
    let view = scrollView.terminalView
    let row = Int((scrollView.contentView.bounds.minY / view.cellSize.height).rounded())
    let terminal = view.session.terminal
    return terminal.text(of: view.line(at: row))
}
