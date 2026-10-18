import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalMenuTests {
    @Test func selectsAllTheText() async throws {
        let session = TerminalSession(running: "seq 1 30; printf 'last'")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForExit()
        #expect(view.selectedText == nil)
        view.selectAll(nil)
        let lines = try #require(view.selectedText).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.prefix(3) == ["1", "2", "3"])
        #expect(lines.contains("30"))
        #expect(lines.last == "last")
    }

    @Test func showsTheEditMenu() async throws {
        let session = TerminalSession(running: "printf 'text'")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForExit()
        let event = try mouseEvent(.rightMouseDown, row: 0, column: 0, in: view)
        let menu = try #require(view.menu(for: event))
        #expect(
            menu.items.map(\.action) == [
                #selector(view.copy(_:)), #selector(view.paste(_:)), #selector(view.selectAll(_:)),
            ])
        #expect(menu.items.allSatisfy { $0.target === view })
        #expect(!view.validateMenuItem(menu.items[0]))
        _ = (menu.items[2].target as? NSObject)?.perform(menu.items[2].action, with: menu.items[2])
        #expect(view.validateMenuItem(menu.items[0]))
        #expect(view.selectedText == "text")
    }

    @Test func reportsAForegroundProcess() async throws {
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/zsh"),
                arguments: ["-f", "-i"],
                environment: ["HOME": "/nonexistent", "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin"]
            )
        )
        #expect(!session.hasForegroundProcess)
        try session.start()
        session.send("echo ready\r")
        await session.waitForText("ready")
        #expect(!session.hasForegroundProcess)
        session.send("sleep 30\r")
        while !session.hasForegroundProcess {
            try await Task.sleep(for: .milliseconds(10))
        }
        session.send("\u{3}")
        while session.hasForegroundProcess {
            try await Task.sleep(for: .milliseconds(10))
        }
        session.send("exit\r")
        await session.waitForExit()
        #expect(!session.hasForegroundProcess)
    }
}
