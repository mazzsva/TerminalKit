import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ShellIntegrationTests {
    private let home: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = try #require(realpath(directory.path(percentEncoded: false), nil))
        defer { free(path) }
        home = URL(filePath: String(cString: path))
        try write("", to: ".zshrc")
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func recordsTheCommands(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("echo hi\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        session.send(Array("false\r".utf8))
        await session.waitForCommands { $0.count == 2 && $0[1].endDate != nil }

        #expect(session.commands.map(\.text) == ["echo hi", "false"])
        #expect(session.commands.map(\.exitStatus) == [0, 1])
        #expect(session.commands.map(\.id) == [0, 1])
        #expect(session.commands[0].directory?.path(percentEncoded: false) == home.path(percentEncoded: false))
        let command = session.commands[0]
        #expect(command.startDate <= command.endDate ?? .distantPast)
        #expect(session.lines.contains("hi"))
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func readsTheOutputOfACommand(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("printf 'a\\n\\tb\\n'\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.output(of: session.commands[0]) == "a\n        b\n")
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func reportsTheCurrentDirectory(shell: String) async throws {
        try FileManager.default.createDirectory(at: home.appending(path: "a b/é%20"), withIntermediateDirectories: true)
        let session = try startedSession(shell)
        session.send(Array("cd 'a b/é%20'\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.currentDirectory?.path(percentEncoded: false) == home.path(percentEncoded: false) + "/a b/é%20")
        #expect(session.currentDirectory?.isFileURL == true)
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func recordsAnInterruptedCommand(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("sleep 30\r".utf8))
        await session.waitForCommands { $0.count == 1 }
        #expect(session.commands[0].endDate == nil)
        session.send([3])
        await session.waitForCommands { $0.first?.endDate != nil }
        #expect(session.commands[0].exitStatus == 130)
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func recordsACommandThatRunsInASubshell(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("(exit 3)\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        session.send(Array("{ true; } &\r".utf8))
        await session.waitForCommands { $0.count == 2 && $0[1].endDate != nil }
        session.send(Array("(echo m\recho n)\r".utf8))
        await session.waitForCommands { $0.count == 3 && $0[2].endDate != nil }
        let lines = shell == "/bin/bash" ? "(echo m; echo n)" : "(echo m\necho n)"
        #expect(session.commands.map(\.text) == ["(exit 3)", "{ true; } &", lines])
        #expect(session.commands.map(\.exitStatus) == [3, 0, 0])
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func recordsNoCommandForAnInterruptedLine(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("true\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        session.send(Array("(echo typed)".utf8) + [3])
        session.send(Array("\rfalse\r".utf8))
        await session.waitForCommands { $0.count == 2 && $0[1].endDate != nil }
        #expect(session.commands.map(\.text) == ["true", "false"])
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func recordsNoCommandForTheSavedHistory(shell: String) async throws {
        try write("(old)\n", to: "history")
        let session = try startedSession(
            shell,
            environment: ["HISTFILE": home.appending(path: "history").path(percentEncoded: false)]
        )
        session.send(Array("true\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.commands.map(\.text) == ["true"])
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func ignoresTheMarksOfPrograms(shell: String) async throws {
        let session = try startedSession(shell)
        let forgery = "printf '\\033]133;C;cmdline_url=forged\\007\\033]133;D;7\\007\\033]133;A\\007'"
        session.send(Array("\(forgery)\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        session.send(Array("true\r".utf8))
        await session.waitForCommands { $0.count == 2 && $0[1].endDate != nil }
        #expect(session.commands.map(\.text) == [forgery, "true"])
        #expect(session.commands.map(\.exitStatus) == [0, 0])
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func recordsNoCommandForAnEmptyLine(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("\r\r   \rtrue\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.commands.map(\.text) == ["true"])
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func leavesNoVariablesToChildProcesses(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("env | grep -c -e TERMINALKIT -e ZDOTDIR\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.lines.contains("0"))
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func finishesTheLastCommandWhenTheShellExits(shell: String) async throws {
        let session = try startedSession(shell)
        session.send(Array("exit\r".utf8))
        await session.waitForExit()
        #expect(session.commands.map(\.text) == ["exit"])
        #expect(session.commands[0].endDate != nil)
        #expect(session.commands[0].exitStatus == nil)
    }

    @Test func loadsTheStartupFilesOfZsh() async throws {
        try write("export ZDOTDIR=\"$HOME/config\"\nexport FROM=zshenv", to: ".zshenv")
        try FileManager.default.createDirectory(at: home.appending(path: "config"), withIntermediateDirectories: true)
        try write("export FROM=\"$FROM-zprofile\"", to: "config/.zprofile")
        try write("export FROM=\"$FROM-zshrc\"\nPS1='custom> '", to: "config/.zshrc")
        try write("export FROM=\"$FROM-zlogin\"", to: "config/.zlogin")
        let session = try startedSession("/bin/zsh")
        session.send(Array("echo $FROM; [ \"$ZDOTDIR\" = \"$HOME/config\" ] && echo same\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.lines.contains("zshenv-zprofile-zshrc-zlogin"))
        #expect(session.lines.contains("same"))
        #expect(session.lines.contains { $0.hasPrefix("custom> echo") })
    }

    @Test func marksThePromptOfATheme() async throws {
        try write(
            """
            theme() { PS1=$'top line\\ntheme %# '; RPS1='right' }
            precmd_functions+=(theme)
            """,
            to: ".zshrc"
        )
        let session = try startedSession("/bin/zsh")
        session.send(Array("echo one\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        session.send(Array("echo two\r".utf8))
        await session.waitForCommands { $0.count == 2 && $0[1].endDate != nil }
        #expect(session.commands.map(\.text) == ["echo one", "echo two"])
        let prompts = session.terminal.commands.compactMap(\.prompt)
        #expect(prompts.count == 2)
        let terminal = session.terminal
        let lines = (terminal.scrollback + terminal.screen).map { String($0.map(terminal.character(of:))) }
        #expect(prompts.allSatisfy { lines[$0.row - terminal.removedScrollbackCount].hasPrefix("top line") })
    }

    @Test func reflowsTheTopLinesOfABashPrompt() async throws {
        try write("PS1='top line of a long prompt here\\nbash$ '", to: ".bash_profile")
        let session = try startedSession("/bin/bash")
        await session.waitForText("bash$")
        session.resize(columns: 10, rows: 24)
        #expect(session.lines.contains("f a long p"))
        #expect(session.lines.contains("rompt here"))
    }

    @Test func keepsTheTopLinesOfAZshPromptForTheShell() async throws {
        try write("PS1=$'top line of a long prompt here\\nzsh%% '", to: ".zshrc")
        let session = try startedSession("/bin/zsh")
        await session.waitForText("zsh%")
        session.resize(columns: 10, rows: 24)
        #expect(!session.lines.contains("f a long p"))
        #expect(session.lines.contains("top line o"))
    }

    @Test func keepsTheZDOTDIROfTheEnvironment() async throws {
        try FileManager.default.createDirectory(at: home.appending(path: "config"), withIntermediateDirectories: true)
        try write("export FROM=zshrc", to: "config/.zshrc")
        let directory = home.appending(path: "config").path(percentEncoded: false)
        let session = try startedSession("/bin/zsh", environment: ["ZDOTDIR": directory])
        session.send(Array("echo $FROM; [ \"$ZDOTDIR\" = \"$HOME/config\" ] && echo same\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.lines.contains("zshrc"))
        #expect(session.lines.contains("same"))
    }

    @Test func loadsTheStartupFilesOfALoginBash() async throws {
        try write("export FROM=profile", to: ".bash_profile")
        try write("export FROM=bashrc", to: ".bashrc")
        let session = try startedSession("/bin/bash")
        session.send(Array("echo $FROM\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.lines.contains("profile"))
    }

    @Test func loadsTheStartupFileOfAnInteractiveBash() async throws {
        try write("export FROM=profile", to: ".bash_profile")
        try write("export FROM=bashrc", to: ".bashrc")
        let session = try startedSession("/bin/bash", arguments: [])
        session.send(Array("echo $FROM\r".utf8))
        await session.waitForCommands { $0.count == 1 && $0[0].endDate != nil }
        #expect(session.lines.contains("bashrc"))
    }

    @Test func recordsNoCommandsWithoutTheIntegration() async throws {
        let session = try startedSession("/bin/zsh", usesShellIntegration: false)
        session.send(Array("echo $ZDOTDIR-done\r".utf8))
        await session.waitForText("-done")
        session.send(Array("exit\r".utf8))
        await session.waitForExit()
        #expect(session.commands.isEmpty)
        #expect(session.currentDirectory == nil)
    }

    @Test func showsTheCommandsOfTheMarks() async throws {
        let session = TerminalSession(
            running: """
                printf '\\033]133;C;cmdline_url=a\\007\\033]133;D;2\\007\\033]133;C;cmdline_url=b\\007'
                read line
                printf '\\033]133;D;0\\007'
                """
        )
        try session.start()
        await session.waitForCommands { $0.count == 2 }
        #expect(session.commands.map(\.text) == ["a", "b"])
        #expect(session.commands.map(\.exitStatus) == [2, nil])
        #expect(session.commands[0].endDate != nil)
        #expect(session.commands[1].endDate == nil)

        session.send(Array("\r".utf8))
        await session.waitForExit()
        #expect(session.commands.map(\.exitStatus) == [2, 0])
        #expect(session.commands[1].endDate != nil)
    }

    @Test func dropsTheOldestCommands() async throws {
        let session = TerminalSession(
            running: """
                i=0
                while [ $i -lt 11001 ]; do
                    printf '\\033]133;C;cmdline_url=%d\\007\\033]133;D;0\\007' $i
                    i=$((i + 1))
                done
                """
        )
        try session.start()
        await session.waitForExit()
        #expect(session.commands.count == 10_000)
        #expect(session.commands.first?.id == 1_001)
        #expect(session.commands.first?.text == "1001")
        #expect(session.commands.last?.id == 11_000)
        #expect(session.commands.last?.text == "11000")
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: home.appending(path: path))
    }

    private func startedSession(
        _ shell: String,
        arguments: [String] = ["-l"],
        environment: [String: String] = [:],
        usesShellIntegration: Bool = true
    ) throws -> TerminalSession {
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: shell),
                arguments: arguments,
                environment: [
                    "HOME": home.path(percentEncoded: false), "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin",
                    "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "SHELL_SESSIONS_DISABLE": "1",
                ]
                .merging(environment) { $1 },
                currentDirectoryURL: home,
                usesShellIntegration: usesShellIntegration
            )
        )
        try session.start()
        return session
    }
}

@MainActor
struct ShellIntegrationConfigurationTests {
    private let directory = URL(filePath: "/scripts")

    @Test func usesTheIntegrationForTheLoginShell() {
        #expect(TerminalSession.Configuration.loginShell.usesShellIntegration)
        #expect(!TerminalSession.Configuration(executableURL: URL(filePath: "/bin/zsh")).usesShellIntegration)
    }

    @Test func startsZshFromTheScripts() {
        let configuration =
            TerminalSession.Configuration(
                executableURL: URL(filePath: "/bin/zsh"),
                arguments: ["-l"],
                environment: ["ZDOTDIR": "/config"]
            )
            .integratingShell(scriptsIn: directory, nonce: "n")
        #expect(configuration?.arguments == ["-l"])
        #expect(
            configuration?.environment == [
                "ZDOTDIR": "/scripts/zsh", "TERMINALKIT_ZSH_ZDOTDIR": "/config", "TERMINALKIT_NONCE": "n",
            ])
    }

    @Test func startsZshWithoutAZDOTDIR() {
        let configuration =
            TerminalSession.Configuration(executableURL: URL(filePath: "/opt/bin/zsh"), environment: [:])
            .integratingShell(scriptsIn: directory, nonce: "n")
        #expect(configuration?.environment == ["ZDOTDIR": "/scripts/zsh", "TERMINALKIT_NONCE": "n"])
    }

    @Test(arguments: [([], "rc"), (["-l"], "login"), (["--login"], "login")])
    func startsBashFromTheScript(arguments: [String], kind: String) {
        let configuration =
            TerminalSession.Configuration(
                executableURL: URL(filePath: "/bin/bash"),
                arguments: arguments,
                environment: [:]
            )
            .integratingShell(scriptsIn: directory, nonce: "n")
        #expect(configuration?.arguments == ["--rcfile", "/scripts/bash/terminalkit.bash"])
        #expect(configuration?.environment == ["TERMINALKIT_BASH_INJECT": kind, "TERMINALKIT_NONCE": "n"])
    }

    @Test(arguments: [("/bin/bash", ["-c", "true"]), ("/bin/sh", ["-l"]), ("/opt/bin/fish", ["-l"])])
    func keepsOtherShells(shell: String, arguments: [String]) {
        let configuration =
            TerminalSession.Configuration(
                executableURL: URL(filePath: shell),
                arguments: arguments,
                environment: [:]
            )
            .integratingShell(scriptsIn: directory, nonce: "n")
        #expect(configuration == nil)
    }

    @Test func installsTheScriptsOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let folder = try ShellIntegration.install(in: directory)
        #expect(try ShellIntegration.install(in: directory) == folder)
        let zshenv = folder.appending(path: "zsh/.zshenv")
        try FileManager.default.removeItem(at: zshenv)
        try Data("changed".utf8).write(to: folder.appending(path: "bash/terminalkit.bash"))

        #expect(try ShellIntegration.install(in: directory) == folder)
        #expect(try String(contentsOf: zshenv, encoding: .utf8).contains("TERMINALKIT_ZSH_ZDOTDIR"))
        let bash = try String(contentsOf: folder.appending(path: "bash/terminalkit.bash"), encoding: .utf8)
        #expect(bash.contains("133;C"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).count == 1)
    }
}

extension TerminalSession {
    fileprivate func waitForCommands(_ isComplete: @escaping ([Command]) -> Bool) async {
        for await commands in Observations({ self.commands }) where isComplete(commands) {
            return
        }
    }
}
