import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalLinkSafetyTests {
    @Test(arguments: ["👨\u{200D}👩", "🇧🇷", "e\u{301}", "中"])
    func detectsAURLAfterACluster(prefix: String) async throws {
        let session = TerminalSession(running: "printf '\(prefix) https://example.com/x'")
        session.resize(columns: 40, rows: 4)
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForExit()
        let line = session.terminal.screen[0]
        let column = try #require(line.indices.first { session.terminal.character(of: line[$0]) == "h" })
        let link = view.link(atRow: 0, column: column)
        #expect(link?.url == URL(string: "https://example.com/x"))
        #expect(link?.spans.first?.columns.lowerBound == column)
    }

    @Test func findsTheURLUnderThePointerAmongMany() async throws {
        let items = (0 ..< 30).map { "e\u{301} https://e.co/\($0)," }.joined(separator: " ")
        let session = TerminalSession(running: "printf '\(items)'")
        session.resize(columns: 40, rows: 20)
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForExit()
        let terminal = session.terminal
        var cells: [(row: Int, column: Int)] = []
        var text = ""
        for row in terminal.screen.indices {
            for column in terminal.screen[row].indices where terminal.screen[row][column].width > 0 {
                cells.append((row, column))
                text.append(terminal.character(of: terminal.screen[row][column]))
            }
        }
        for number in [0, 7, 17, 29] {
            let range = try #require(text.range(of: "https://e.co/\(number),"))
            let cell = cells[text.distance(from: text.startIndex, to: range.lowerBound) + 5]
            let link = view.link(atRow: cell.row, column: cell.column)
            #expect(link?.url == URL(string: "https://e.co/\(number)"))
        }
    }

    @Test func keepsTheSelectionWhenACommandClickOpensALink() async throws {
        let (view, window) = try await clickView(running: "printf 'some text\\r\\nhttps://example.com/x'")
        var opened: [TerminalContentView.LinkAction] = []
        view.performLinkAction = { opened.append($0) }
        try drag(in: view, row: 0, from: 0, to: 4)
        let selected = view.selectedText
        try drag(in: view, row: 1, from: 3, to: 10, modifierFlags: .command)
        #expect(opened.count == 1)
        #expect(view.selectedText == selected)
        #expect(window.contentView === view)
    }

    @Test func selectsAfterALinkClickWithoutAMouseUp() async throws {
        let (view, window) = try await clickView(running: "printf 'some text\\r\\nhttps://example.com/x'")
        view.performLinkAction = { _ in }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 3, in: view, modifierFlags: .command))
        try drag(in: view, row: 0, from: 0, to: 4)
        #expect(view.selectedText == "some")
        #expect(window.contentView === view)
    }

    @Test func reportsNoDragAfterACommandClickOpensALink() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf 'https://example.com/x\\r\\n\\033[?1002h'; dd bs=1 count=6 2>/dev/null | od -An -tx1"
        )
        session.resize(columns: 40, rows: 4)
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        var opened = 0
        view.performLinkAction = { _ in opened += 1 }
        try session.start()
        for await tracking in Observations({ session.liveTerminal.mouseTracking }) where tracking == .drags {
            break
        }
        try drag(in: view, row: 0, from: 3, to: 9, modifierFlags: .command)
        view.keyDown(with: try keyDown("abcdef"))
        #expect(await session.linesAfterExit().contains("61  62  63  64  65  66"))
        #expect(opened == 1)
        #expect(window.contentView === view)
    }

    @Test func revealsAnAppOrAProgramBehindASymbolicLink() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appending(path: "Tool.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let program = directory.appending(path: "program")
        try Data("#!/bin/sh\n".utf8).write(to: program)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: program.path(percentEncoded: false))
        for (name, target) in [("notes", directory.appending(path: "Tool.app")), ("readme", program)] {
            let link = directory.appending(path: name)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(TerminalContentView.action(for: link) == .reveal(link))
        }
    }

    @Test(arguments: ["webloc", "fileloc", "inetloc", "mobileconfig", "prefpane", "saver"])
    func revealsALocationOrProfileFile(pathExtension: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "readme.\(pathExtension)")
        try Data("<plist><dict><key>URL</key><string>x-scheme://run</string></dict></plist>".utf8).write(to: file)
        #expect(TerminalContentView.action(for: file) == .reveal(file))
    }
}

@MainActor
private func clickView(running script: String) async throws -> (TerminalContentView, NSWindow) {
    let session = TerminalSession(running: script)
    session.resize(columns: 40, rows: 4)
    let view = TerminalContentView(session: session)
    let window = NSWindow(contentView: view)
    view.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
    try session.start()
    await session.waitForExit()
    return (view, window)
}

@MainActor
private func drag(
    in view: TerminalContentView,
    row: Int,
    from start: Int,
    to end: Int,
    modifierFlags: NSEvent.ModifierFlags = []
) throws {
    view.mouseDown(
        with: try mouseEvent(.leftMouseDown, row: row, column: start, in: view, modifierFlags: modifierFlags))
    view.mouseDragged(
        with: try mouseEvent(.leftMouseDragged, row: row, column: end, in: view, modifierFlags: modifierFlags))
    view.mouseUp(with: try mouseEvent(.leftMouseUp, row: row, column: end, in: view, modifierFlags: modifierFlags))
}
