import Foundation
import Synchronization
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSessionTests {
    @Test func startsTheLoginShellThroughLogin() {
        let configuration = TerminalSession.Configuration.loginShell
        #expect(configuration.executableURL == URL(filePath: "/usr/bin/login"))
        #expect(configuration.arguments == ["-pf", TerminalSession.Configuration.userName])
        #expect(configuration.currentDirectoryURL == nil)
    }

    @Test func startsTheLoginShellInAFolderThroughLogin() {
        let user = TerminalSession.Configuration.userName
        var configuration = TerminalSession.Configuration.loginShell
        configuration.currentDirectoryURL = URL(filePath: "/tmp")
        #expect(configuration.arguments == TerminalSession.Configuration.loginArguments(in: URL(filePath: "/tmp")))
        #expect(configuration.arguments.prefix(4) == ["-pfl", user, "/bin/bash", "-c"])
        configuration.currentDirectoryURL = nil
        #expect(configuration.arguments == ["-pf", user])
        #expect(configuration.isLoginShell)
        #expect(
            TerminalSession.Configuration.loginArguments(in: URL(filePath: "/tmp"), shellURL: URL(filePath: "/bin/zsh"))
                == ["-pfl", user, "/bin/bash", "-c", "exec -la zsh /bin/zsh"])
        #expect(
            TerminalSession.Configuration.loginArguments(
                in: URL(filePath: "/tmp"), shellURL: URL(filePath: "/a b/it's"))
                == ["-pfl", user, "/bin/bash", "-c", "exec -la 'it'\\''s' '/a b/it'\\''s'"])
    }

    @Test func keepsTheArgumentsOfTheHostInAFolder() {
        var configuration = TerminalSession.Configuration.loginShell
        configuration.arguments = ["-pfq", "user", "/bin/sh"]
        configuration.currentDirectoryURL = URL(filePath: "/tmp")
        #expect(configuration.arguments == ["-pfq", "user", "/bin/sh"])
        #expect(!configuration.isLoginShell)
        var other = TerminalSession.Configuration.loginShell
        other.executableURL = URL(filePath: "/bin/zsh")
        other.currentDirectoryURL = URL(filePath: "/tmp")
        #expect(other.arguments == ["-pf", TerminalSession.Configuration.userName])
        #expect(!other.isLoginShell)
    }

    @Test func runsTheShellInTheFolderThroughLogin() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shell = folder.appending(path: "shell")
        try Data("#!/bin/sh\necho \"in ${PWD##*/} as $USER\"\n".utf8).write(to: shell)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: shell.path(percentEncoded: false))
        let arguments = TerminalSession.Configuration.loginArguments(in: folder, shellURL: shell)
        try #require(arguments.first == "-pfl")
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/usr/bin/login"),
                arguments: arguments,
                environment: ["PATH": "/usr/bin:/bin"],
                currentDirectoryURL: folder
            ))
        try session.start()
        let lines = await session.linesAfterExit()
        #expect(lines.contains("in \(folder.lastPathComponent) as \(TerminalSession.Configuration.userName)"))
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func describesTheTerminalToTheLoginShell() {
        let environment = TerminalSession.Configuration
            .loginShell(inheriting: ["TERM": "dumb", "LANG": "en_US.UTF-8", "PATH": "/bin"])
            .environment
        #expect(
            environment == [
                "TERM": "xterm-256color", "COLORTERM": "truecolor", "LANG": "en_US.UTF-8",
                "TERM_PROGRAM": "Apple_Terminal", "TERM_PROGRAM_VERSION": "488", "CLAUDE_CODE_FORCE_SYNC_OUTPUT": "1",
                "PATH": "/bin",
            ])
    }

    @Test func describesTheTerminalToAnyProcess() {
        let environment = TerminalSession.Configuration(executableURL: URL(filePath: "/bin/sh")).environment
        let inherited = ProcessInfo.processInfo.environment
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["COLORTERM"] == "truecolor")
        #expect(environment["PATH"] == inherited["PATH"])
        #expect(environment["TERM_PROGRAM"] == "Apple_Terminal")
        #expect(environment["TERM_PROGRAM_VERSION"] == "488")
        #expect(environment["CLAUDE_CODE_FORCE_SYNC_OUTPUT"] == inherited["CLAUDE_CODE_FORCE_SYNC_OUTPUT"] ?? "1")
        #expect(environment["TERM_SESSION_ID"] == nil)
    }

    @Test func keepsTheHistoryFileWithTheTerminalName() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/zsh"),
                arguments: ["-l", "-i"],
                environment: TerminalSession.Configuration.terminalEnvironment(
                    inheriting: ["HOME": home.path(percentEncoded: false), "PATH": "/usr/bin:/bin"]),
                currentDirectoryURL: home
            ))
        try session.start()
        for await url in Observations({ session.currentDirectoryURL }) where url != nil {
            break
        }
        session.send("[ \"$HISTFILE\" = \"$HOME/.zsh_history\" ] && echo sa\"\"me\r")
        await session.waitForText("same")
        session.send("exit\r")
        let lines = await session.linesAfterExit()
        #expect(!lines.contains { $0.contains("Saving session") })
        let sessions = home.appending(path: ".zsh_sessions").path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: sessions))
    }

    @Test func keepsTheClaudeCodeSettingOfTheUser() {
        let environment = TerminalSession.Configuration.terminalEnvironment(
            inheriting: ["CLAUDE_CODE_FORCE_SYNC_OUTPUT": "0"])
        #expect(environment["CLAUDE_CODE_FORCE_SYNC_OUTPUT"] == "0")
    }

    @Test func keepsTheLanguageOfTheUser() {
        let environment = TerminalSession.Configuration.terminalEnvironment(
            inheriting: ["LANG": "pt_BR.UTF-8"], locale: Locale(identifier: "de_DE"))
        #expect(environment["LANG"] == "pt_BR.UTF-8")
    }

    @Test func setsTheLanguageFromTheLocale() {
        let environment = TerminalSession.Configuration.terminalEnvironment(
            inheriting: [:], locale: Locale(identifier: "de_CH"))
        #expect(environment["LANG"] == "de_CH.UTF-8")
    }

    @Test func setsTheEnglishLanguageForALocaleThatIsNotInstalled() {
        let environment = TerminalSession.Configuration.terminalEnvironment(
            inheriting: [:], locale: Locale(identifier: "en_BR"))
        #expect(environment["LANG"] == "en_US.UTF-8")
    }

    @Test func removesTheIdentityOfTheParentTerminal() {
        let environment = TerminalSession.Configuration
            .loginShell(
                inheriting: [
                    "TERM_PROGRAM": "Apple_Terminal", "TERM_PROGRAM_VERSION": "470", "TERM_SESSION_ID": "1",
                    "TMUX": "/tmp/tmux-501/default,1,0", "TMUX_PANE": "%0", "STY": "1.ttys000.host",
                    "LC_TERMINAL": "iTerm2", "LC_TERMINAL_VERSION": "3.5.0", "ITERM_SESSION_ID": "w0t0p0:1",
                    "ITERM_PROFILE": "Default", "KITTY_WINDOW_ID": "1", "KITTY_PID": "1", "COLORFGBG": "15;0",
                    "COLUMNS": "20", "LINES": "5", "TERMINFO": "/tmp/terminfo", "CLAUDECODE": "1",
                    "CLAUDE_CODE_CHILD_SESSION": "1", "CURSOR_TRACE_ID": "1", "TERMINAL_EMULATOR": "JetBrains-JediTerm",
                    "ALACRITTY_LOG": "/tmp/Alacritty-1.log", "ALACRITTY_WINDOW_ID": "1", "WEZTERM_PANE": "0",
                    "WT_SESSION": "1", "VTE_VERSION": "7600", "KONSOLE_VERSION": "230804",
                    "GNOME_TERMINAL_SERVICE": ":1.1", "XTERM_VERSION": "XTerm(390)", "TERMINATOR_UUID": "urn:uuid:1",
                    "TILIX_ID": "1", "ZED_TERM": "true", "ZELLIJ": "0", "CLAUDE_CODE_SSE_PORT": "1",
                    "SSH_CONNECTION": "10.0.0.1 1 10.0.0.2 22", "SSH_CLIENT": "10.0.0.1 1 22",
                    "SSH_TTY": "/dev/ttys000", "LANG": "en_US.UTF-8", "SSH_AUTH_SOCK": "/tmp/agent",
                    "GIT_ASKPASS": "/tmp/askpass", "VSCODE_GIT_IPC_HANDLE": "/tmp/vscode-git.sock",
                ]
            )
            .environment
        #expect(
            environment == [
                "TERM": "xterm-256color", "COLORTERM": "truecolor", "LANG": "en_US.UTF-8",
                "TERM_PROGRAM": "Apple_Terminal", "TERM_PROGRAM_VERSION": "488", "CLAUDE_CODE_FORCE_SYNC_OUTPUT": "1",
                "SSH_AUTH_SOCK": "/tmp/agent", "GIT_ASKPASS": "/tmp/askpass",
                "VSCODE_GIT_IPC_HANDLE": "/tmp/vscode-git.sock",
            ])
    }

    @Test func runsTheCommandInTheInteractiveLoginShell() {
        let configuration = TerminalSession.Configuration.loginShell(
            running: ["claude", "--resume", "it's"], shellURL: URL(filePath: "/bin/zsh"))
        let loginShell = TerminalSession.Configuration.loginShell
        #expect(configuration.executableURL == loginShell.executableURL)
        #expect(
            configuration.arguments == [
                "-pfql", TerminalSession.Configuration.userName, "/bin/zsh", "-l", "-i", "-c",
                "exec -- 'claude' '--resume' 'it'\\''s'",
            ])
        #expect(configuration.environment == loginShell.environment)
        #expect(configuration.currentDirectoryURL == .homeDirectory)
        #expect(loginShell.isLoginShell)
        #expect(!configuration.isLoginShell)
    }

    @Test func quotesTheBackslashesForFish() {
        let fish = URL(filePath: "/opt/homebrew/bin/fish")
        let arguments = TerminalSession.Configuration.shellArguments(
            running: ["printf", "a\\b", "dir\\", "it's"], shellURL: fish)
        #expect(arguments == ["-l", "-i", "-c", "exec -- 'printf' 'a\\\\b' 'dir\\\\' 'it'\\''s'"])
    }

    @Test func keepsTheBackslashesForZsh() {
        let arguments = TerminalSession.Configuration.shellArguments(
            running: ["printf", "a\\b", "dir\\"], shellURL: URL(filePath: "/bin/zsh"))
        #expect(arguments == ["-l", "-i", "-c", "exec -- 'printf' 'a\\b' 'dir\\'"])
    }

    @Test func startsIdle() {
        #expect(TerminalSession(running: "exit").state == .idle)
    }

    @Test func runsTheProcess() async throws {
        let session = TerminalSession(running: "exit")
        try session.start()
        #expect(session.state == .running)
        await session.waitForExit()
    }

    @Test func showsTheOutputOfTheProcess() async throws {
        let session = TerminalSession(running: "printf 'hello\\nworld'")
        try session.start()
        await session.waitForExit()
        #expect(session.lines.prefix(2) == ["hello", "world"])
    }

    @Test func reportsTheExitOfTheProcess() async throws {
        let session = TerminalSession(running: "exit 3")
        try session.start()
        await session.waitForExit()
        #expect(session.state == .exited(.exit(3)))
    }

    @Test func countsTheBellsOfTheProcess() async throws {
        let session = TerminalSession(running: "printf 'a\\a\\033]0;t\\007\\a'")
        try session.start()
        await session.waitForExit()
        #expect(session.bellCount == 2)
    }

    @Test func showsTheTitleOfTheProcess() async throws {
        let session = TerminalSession(running: "printf '\\033]0;Title\\007'")
        try session.start()
        await session.waitForExit()
        #expect(session.title == "Title")
    }

    @Test func showsTheCurrentDirectoryOfTheProcess() async throws {
        let session = TerminalSession(running: "printf '\\033]7;file:///tmp/a%%20b\\007'")
        try session.start()
        await session.waitForExit()
        #expect(session.currentDirectoryURL == URL(filePath: "/tmp/a b"))
    }

    @Test func keepsTheTitleForOtherOutput() async throws {
        let session = TerminalSession(running: "printf '\\033]0;Title\\007'; read line; echo more")
        try session.start()
        for await title in Observations({ session.title }) where title == "Title" {
            break
        }
        let changes = Mutex(0)
        withObservationTracking {
            _ = session.title
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        session.send(Array("\r".utf8))
        await session.waitForExit()
        #expect(session.lines.contains("more"))
        #expect(changes.withLock { $0 } == 0)
    }

    @Test func sendsInputToTheProcess() async throws {
        let session = TerminalSession(running: "read line; echo \"got $line\"")
        try session.start()
        session.send(Array("hello\r".utf8))
        await session.waitForExit()
        #expect(session.lines.contains("got hello"))
    }

    @Test func answersTheQueriesOfTheProcess() async throws {
        let session = TerminalSession(running: "stty raw -echo; printf '\\033[6n'; head -c 6 | od -An -tx1")
        try session.start()
        await session.waitForExit()
        #expect(session.lines.contains("1b  5b  31  3b  31  52"))
    }

    @Test func dropsTheRepliesThatTheProcessDoesNotRead() async throws {
        let session = TerminalSession(
            running: """
                stty raw -echo; q=$(printf '\\033[c%.0s' $(seq 1000)); i=0
                while :; do printf %s "$q"; i=$((i + 1)); [ $i = 1000 ] && echo "flooded $$"; done
                """
        )
        try session.start()
        await session.waitForText("flooded")
        let line = try #require(session.lines.first { $0.hasPrefix("flooded") })
        let processIdentifier = try #require(pid_t(line.dropFirst("flooded ".count)))
        #expect(try #require(session.pseudoTerminal).unsentInputCount < 5 << 20)
        #expect(kill(processIdentifier, SIGKILL) == 0)
        await session.waitForExit()
    }

    @Test func keepsTheMainActorFreeWhileOutputFloods() async throws {
        let session = TerminalSession(running: "exec yes \"$(printf '\\033[m%.0s' $(seq 3000))end\"")
        try session.start()
        await session.waitForText("end")
        for _ in 0 ..< 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        session.send([3])
        await session.waitForExit()
        #expect(session.state == .exited(.uncaughtSignal(SIGINT)))
    }

    @Test func startsTheProcessWithTheSizeOfTheScreen() async throws {
        let session = TerminalSession(running: "stty size")
        session.resize(columns: 100, rows: 30)
        try session.start()
        await session.waitForExit()
        #expect(session.lines.first == "30 100")
    }

    @Test func reportsThePixelSizeOfTheScreen() async throws {
        let session = TerminalSession(
            running: "perl -e 'ioctl(STDIN, 0x40087468, $size = \"\\0\" x 8); print join(\" \", unpack(\"S4\", $size))'"
        )
        session.resize(columns: 100, rows: 30, cellSize: CGSize(width: 8, height: 16))
        try session.start()
        await session.waitForExit()
        #expect(session.lines.first == "30 100 800 480")
    }

    @Test func reportsThePixelSizeAfterTheCellSizeChanges() async throws {
        let session = TerminalSession(
            running: """
                trap 'perl -e "ioctl(STDIN, 0x40087468, \\$s = chr(0) x 8); print join(chr(32), unpack(chr(83).4, \\$s))"; exit' WINCH; \
                echo ready; while :; do sleep 0.1; done
                """
        )
        session.resize(columns: 100, rows: 30)
        try session.start()
        await session.waitForText("ready")
        session.resize(columns: 100, rows: 30, cellSize: CGSize(width: 8, height: 16))
        await session.waitForExit()
        #expect(session.lines.contains("30 100 800 480"))
    }

    @Test func resizesTheProcess() async throws {
        let session = TerminalSession(running: "trap 'stty size; exit' WINCH; echo ready; while :; do sleep 0.1; done")
        try session.start()
        await session.waitForText("ready")
        session.resize(columns: 100, rows: 30)
        await session.waitForExit()
        #expect(session.lines.contains("30 100"))
    }

    @Test func passesEachWordOfTheCommandUnchanged() async throws {
        let words = [
            "a b", "it's", "\"q\"", "$HOME", "*", "", "back\\slash", "!x", "~", "café €",
            "x'\u{301}$(/bin/echo injected)'\u{301}",
        ]
        let session = try await runInZsh(["/bin/sh", "-c", "printf '<%s>\\n' \"$@\"", "sh"] + words)
        #expect(session.lines.prefix(words.count) == ArraySlice(words.map { "<\($0)>" }))
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func findsTheCommandOnThePathOfTheShellStartupFiles() async throws {
        let session = try await runInZsh(["tool"], startup: "export PATH=\"$HOME/bin dir:$PATH\"")
        #expect(session.lines.first == "found")
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func runsTheCommandInTheCurrentDirectory() async throws {
        let session = try await runInZsh(["./tool"])
        #expect(session.lines.first == "found")
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func reportsTheExitStatusOfTheCommand() async throws {
        let session = try await runInZsh(["/bin/sh", "-c", "exit 7"], startup: "trap 'exit 1' EXIT")
        #expect(session.state == .exited(.exit(7)))
    }

    @Test func reportsTheSignalOfTheCommand() async throws {
        let session = try await runInZsh(["/bin/sh", "-c", "kill -TERM $$"], startup: "trap 'exit 1' EXIT")
        #expect(session.state == .exited(.uncaughtSignal(SIGTERM)))
    }

    @Test func runsAFirstWordThatStartsWithAHyphenAsTheCommand() async throws {
        let session = try await runInZsh(["-a", "name", "/bin/sh", "-c", "exit 7"])
        #expect(session.state == .exited(.exit(127)))
    }

    @Test func failsWhenTheCommandIsEmpty() async throws {
        let session = try await runInZsh([], startup: "trap 'exit 4' EXIT")
        #expect(session.state == .exited(.exit(1)))
    }

    @Test func throwsWhenTheProcessCannotStart() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/missing")))
        #expect(throws: POSIXError(.ENOENT)) {
            try session.start()
        }
        #expect(session.state == .idle)
    }
}

@MainActor
private func runInZsh(_ command: [String], startup: String = "") async throws -> TerminalSession {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let tool = home.appending(path: "bin dir/tool")
    try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\necho found\n".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))
    try Data(startup.utf8).write(to: home.appending(path: ".zshrc"))
    let zsh = URL(filePath: "/bin/zsh")
    let session = TerminalSession(
        configuration: .init(
            executableURL: zsh,
            arguments: TerminalSession.Configuration.shellArguments(running: command, shellURL: zsh),
            environment: TerminalSession.Configuration.terminalEnvironment(
                inheriting: [
                    "HOME": home.path(percentEncoded: false), "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin",
                ]),
            currentDirectoryURL: tool.deletingLastPathComponent()
        ))
    try session.start()
    await session.waitForExit()
    return session
}
