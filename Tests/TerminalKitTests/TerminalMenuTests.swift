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
        #expect(menu.items.map(\.action) == [#selector(view.copy(_:)), #selector(view.paste(_:))])
        #expect(menu.items.allSatisfy { $0.target === view })
        let textMenu = try #require(NSTextView.defaultMenu)
        #expect(
            menu.items.map(\.title)
                == menu.items.map { item in textMenu.items.first { $0.action == item.action }?.title })
        #expect(
            menu.items.map(\.identifier)
                == menu.items.map { item in textMenu.items.first { $0.action == item.action }?.identifier })
        #expect(textMenu.items.allSatisfy { $0.target !== view })
        #expect(!view.validateMenuItem(menu.items[0]))
        view.selectAll(nil)
        #expect(view.validateMenuItem(menu.items[0]))
        #expect(view.selectedText == "text")
    }

    @Test func offersTheSelectionToServices() async throws {
        let session = TerminalSession(running: "printf 'text'")
        let view = TerminalContentView(session: session)
        let next = ServicesRequestor()
        view.nextResponder = next
        try session.start()
        await session.waitForExit()
        #expect(view.validRequestor(forSendType: .string, returnType: nil) as? ServicesRequestor === next)
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 1), head: .init(line: 0, column: 1))
        #expect(view.validRequestor(forSendType: .string, returnType: nil) as? ServicesRequestor === next)
        view.selectAll(nil)
        #expect(view.validRequestor(forSendType: .string, returnType: nil) as? TerminalContentView === view)
        #expect(view.validRequestor(forSendType: .string, returnType: .string) as? ServicesRequestor === next)
        #expect(view.validRequestor(forSendType: nil, returnType: .string) as? ServicesRequestor === next)
        #expect(view.validRequestor(forSendType: .rtf, returnType: nil) as? ServicesRequestor === next)
    }

    @Test func writesTheSelectionForServices() async throws {
        let session = TerminalSession(
            running: "printf 'text\\033[>1u'; stty raw -echo; echo ready; head -c 1 | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        window.makeFirstResponder(view)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        try session.start()
        await session.waitForText("ready")
        #expect(!view.writeSelection(to: pasteboard, types: [.string]))
        #expect(pasteboard.string(forType: .string) == nil)
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 4))
        pasteboard.setString("old", forType: .rtf)
        let requestor = try #require(
            view.validRequestor(forSendType: .string, returnType: nil) as? NSServicesMenuRequestor)
        #expect(requestor.writeSelection?(to: pasteboard, types: [.init("NSStringPboardType")]) == true)
        #expect(pasteboard.string(forType: .string) == "text")
        #expect(pasteboard.string(forType: .rtf) == nil)
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 20), head: .init(line: 0, column: 30))
        #expect(view.validRequestor(forSendType: .string, returnType: nil) as? TerminalContentView === view)
        #expect(view.writeSelection(to: pasteboard, types: [.string]))
        #expect(pasteboard.string(forType: .string) == "")
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("78"))
    }

    @Test func hidesWritingTools() {
        let view = TerminalContentView(session: TerminalSession(running: "true"))
        #expect((view as NSTextInputTraits).writingToolsBehavior == NSWritingToolsBehavior.none)
    }

    @Test func reportsAForegroundProcess() async throws {
        var configuration = TerminalSession.Configuration(
            executableURL: URL(filePath: "/bin/zsh"),
            arguments: ["-f", "-i"],
            environment: ["HOME": "/nonexistent", "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin"]
        )
        configuration.isLoginShell = true
        let session = TerminalSession(configuration: configuration)
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

    @Test func reportsTheCommandOfALoginShellAsAForegroundProcess() async throws {
        var configuration = TerminalSession.Configuration.loginShell(running: [
            "/bin/sh", "-c", "echo running; exec /bin/sleep 30",
        ])
        configuration.executableURL = URL(filePath: "/bin/zsh")
        configuration.environment = TerminalSession.Configuration.terminalEnvironment(
            inheriting: ["HOME": "/nonexistent", "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin"])
        let session = TerminalSession(configuration: configuration)
        #expect(!session.hasForegroundProcess)
        try session.start()
        await session.waitForText("running")
        #expect(session.hasForegroundProcess)
        session.terminate()
        await session.waitForExit()
        #expect(!session.hasForegroundProcess)
    }

    @Test func reportsTheProgramAsAForegroundProcess() async throws {
        let session = TerminalSession(running: "echo running; exec /bin/sleep 30")
        #expect(!session.hasForegroundProcess)
        try session.start()
        await session.waitForText("running")
        #expect(session.hasForegroundProcess)
        session.terminate()
        await session.waitForExit()
        #expect(!session.hasForegroundProcess)
    }
}

private final class ServicesRequestor: NSResponder {
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        self
    }
}
