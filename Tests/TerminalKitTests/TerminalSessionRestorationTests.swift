import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSessionRestorationTests {
    private let commands =
        "printf '\\033]133;A\\007$ \\033]133;C;cmdline_url=ls\\007a\\r\\n\\033]133;D;0\\007"
        + "\\033]133;A\\007$ \\033]133;C;cmdline_url=false\\007\\033]133;D;1\\007\\033]133;A\\007$ '"

    private func shell(_ script: String) -> TerminalSession.Configuration {
        .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script])
    }

    private func finishedSession(_ script: String) async throws -> TerminalSession {
        let session = TerminalSession(running: script)
        try session.start()
        await session.waitForExit()
        return session
    }

    private func decoded(_ state: TerminalSession.RestorationState) throws -> TerminalSession.RestorationState {
        try JSONDecoder().decode(TerminalSession.RestorationState.self, from: JSONEncoder().encode(state))
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TerminalKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = try #require(realpath(folder.path(percentEncoded: false), nil))
        defer { free(path) }
        return URL(filePath: String(cString: path), directoryHint: .notDirectory)
    }

    @Test func showsTheContentAndTheCommandsBeforeItStarts() async throws {
        let session = try await finishedSession(commands)
        let restored = TerminalSession(configuration: shell("exit"), restoring: try decoded(session.restorationState))
        #expect(restored.state == .idle)
        #expect(restored.lines.prefix(4) == ["$ a", "$", "", ""])
        #expect(restored.commands == session.commands)
        #expect(restored.commands.map(\.text) == ["ls", "false"])
        #expect(restored.commands.map(\.exitStatus) == [0, 1])
    }

    @Test func continuesTheCommandIdentifiers() async throws {
        let session = try await finishedSession(commands)
        let restored = TerminalSession(configuration: shell(commands), restoring: session.restorationState)
        try restored.start()
        await restored.waitForExit()
        #expect(restored.commands.map(\.id) == [0, 1, 2, 3])
        #expect(restored.commands.map(\.text) == ["ls", "false", "ls", "false"])
        #expect(restored.lines.prefix(4) == ["$ a", "$", "$ a", "$ $"])
    }

    @Test func finishesARunningCommand() async throws {
        let session = TerminalSession(
            running: "printf '\\033]133;A\\007$ \\033]133;C;cmdline_url=sleep\\007'; exec sleep 30"
        )
        try session.start()
        for await commands in Observations({ session.commands }) where !commands.isEmpty {
            break
        }
        let state = session.restorationState
        session.terminate()
        await session.waitForExit()
        let restored = TerminalSession(configuration: shell("exit"), restoring: state)
        let command = try #require(restored.commands.first)
        #expect(command.text == "sleep")
        #expect(command.exitStatus == nil)
        #expect(command.endDate != nil)
    }

    @Test func startsInTheSavedFolder() async throws {
        let saved = try folder()
        defer { try? FileManager.default.removeItem(at: saved) }
        let session = try await finishedSession("printf '\\033]7;\(saved.absoluteString)\\007'")
        let restored = TerminalSession(configuration: shell("pwd -P"), restoring: session.restorationState)
        #expect(restored.currentDirectory?.lastPathComponent == saved.lastPathComponent)
        restored.resize(columns: 300, rows: 5)
        try restored.start()
        await restored.waitForExit()
        #expect(restored.lines.first == saved.path(percentEncoded: false))
    }

    @Test func startsInTheConfiguredFolderWhenTheSavedFolderIsGone() async throws {
        let saved = try folder()
        let configured = try folder()
        defer { try? FileManager.default.removeItem(at: configured) }
        let session = try await finishedSession("printf '\\033]7;\(saved.absoluteString)\\007'")
        try FileManager.default.removeItem(at: saved)
        var configuration = shell("pwd -P")
        configuration.currentDirectoryURL = configured
        let restored = TerminalSession(configuration: configuration, restoring: session.restorationState)
        restored.resize(columns: 300, rows: 5)
        try restored.start()
        await restored.waitForExit()
        #expect(restored.lines.first == configured.path(percentEncoded: false))
    }

    @Test func startsInTheConfiguredFolderWhenTheSavedFolderIsAFile() async throws {
        let configured = try folder()
        defer { try? FileManager.default.removeItem(at: configured) }
        let file = configured.appending(path: "tool")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        let session = try await finishedSession("printf '\\033]7;\(file.absoluteString)\\007'")
        var configuration = shell("pwd -P")
        configuration.currentDirectoryURL = configured
        let restored = TerminalSession(configuration: configuration, restoring: session.restorationState)
        restored.resize(columns: 300, rows: 5)
        try restored.start()
        await restored.waitForExit()
        #expect(restored.lines.first == configured.path(percentEncoded: false))
    }

    @Test func keepsTheSizeOfTheSavedTerminal() async throws {
        let session = TerminalSession(running: "printf abc")
        session.resize(columns: 30, rows: 7)
        try session.start()
        await session.waitForExit()
        let restored = TerminalSession(configuration: shell("exit"), restoring: session.restorationState)
        #expect(restored.liveTerminal.columns == 30)
        #expect(restored.liveTerminal.rows == 7)
        #expect(restored.lines.first == "abc")
    }
}
