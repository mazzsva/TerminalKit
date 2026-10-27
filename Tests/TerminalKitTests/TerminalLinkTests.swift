import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalLinkTests {
    @Test(arguments: [
        ("see https://example.com.", "https://example.com"),
        ("(https://en.wikipedia.org/wiki/Swift_(language))", "https://en.wikipedia.org/wiki/Swift_(language)"),
        ("go to https://a.com/x, then", "https://a.com/x"),
        ("'https://a.com/q?x=1&y=2'", "https://a.com/q?x=1&y=2"),
        ("<HTTPS://A.COM/>", "HTTPS://A.COM/"),
        ("mail mailto:me@example.com!", "mailto:me@example.com"),
        ("open file:///tmp/a b", "file:///tmp/a"),
        ("ftp://host/file]", "ftp://host/file"),
        ("https://a/" + String(repeating: ")", count: 50_000), "https://a/"),
        ("（https://example.com/docs）", "https://example.com/docs"),
        ("（https://example.com）を参照。", "https://example.com"),
        ("「https://example.com/a」", "https://example.com/a"),
        ("見て https://example.com/a。", "https://example.com/a"),
        ("【https://example.com】", "https://example.com"),
        ("https://ja.wikipedia.org/wiki/A（B）", "https://ja.wikipedia.org/wiki/A（B）"),
        ("{https://a/[b]{c}『d』〔e〕［f］｛g｝}", "https://a/[b]{c}『d』〔e〕［f］｛g｝"),
        ("https://a/x;:?、，！？；：", "https://a/x"),
        ("\"https://a.com/x\"", "https://a.com/x"),
        ("`https://a.com/x`", "https://a.com/x"),
        ("https://a.com/x<b", "https://a.com/x"),
        ("『https://a/x』", "https://a/x"),
        ("〔https://a/x〕", "https://a/x"),
        ("［https://a/x］", "https://a/x"),
        ("｛https://a/x｝", "https://a/x"),
    ])
    func detectsALink(text: String, link: String) {
        let ranges = TerminalContentView.detectedLinks(in: text)
        let characters = Array(text)
        #expect(ranges.map { String(characters[$0]) } == [link])
    }

    @Test(arguments: [
        ("「https://a.com」と「https://b.com」", ["https://a.com", "https://b.com"]),
        ("(https://a.com)(https://b.com)", ["https://a.com", "https://b.com"]),
    ])
    func detectsEachLink(text: String, links: [String]) {
        let characters = Array(text)
        #expect(TerminalContentView.detectedLinks(in: text).map { String(characters[$0]) } == links)
    }

    @Test func detectsLongLinks() {
        let link = "https://a/" + String(repeating: "()", count: 50_000)
        #expect(TerminalContentView.detectedLinks(in: link + ")") == [0 ..< link.count])
        #expect(
            TerminalContentView.detectedLinks(in: String(repeating: "https://a/)", count: 50_000))
                == (0 ..< 50_000).map { $0 * 11 ..< $0 * 11 + 10 })
    }

    @Test(arguments: [
        "no link here", "https:/broken", "javascript:alert(1)", "ssh://host", "see https:// now", "mailto: me",
    ])
    func detectsNoLink(text: String) {
        #expect(TerminalContentView.detectedLinks(in: text).isEmpty)
    }

    @Test func choosesASafeAction() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Tool.app"), withIntermediateDirectories: true)
        try Data("text".utf8).write(to: folder.appending(path: "notes.txt"))
        try Data("open -a Calculator".utf8).write(to: folder.appending(path: "run.command"))
        try Data("#!/bin/sh".utf8).write(to: folder.appending(path: "script"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "script").path(percentEncoded: false))
        let action = { (path: String) in TerminalContentView.action(for: folder.appending(path: path)) }
        #expect(action("notes.txt") == .open(folder.appending(path: "notes.txt")))
        #expect(action("") == .open(folder.appending(path: "")))
        #expect(action("Tool.app") == .reveal(folder.appending(path: "Tool.app")))
        #expect(action("run.command") == .reveal(folder.appending(path: "run.command")))
        #expect(action("script") == .reveal(folder.appending(path: "script")))
        #expect(action("missing") == nil)
        let url = try #require(URL(string: "https://example.com"))
        #expect(TerminalContentView.action(for: url) == .open(url))
        for text in ["zoommtg://join", "javascript:alert(1)", "ssh://host", "x-apple.systempreferences:"] {
            #expect(TerminalContentView.action(for: try #require(URL(string: text))) == nil)
        }
    }

    @Test func findsAHyperlink() async throws {
        let view = try await linkView(
            running: "printf 'x \\033]8;;https://example.com/a\\033\\\\ab\\033]8;;\\033\\\\ c'")
        let link = try #require(view.link(atRow: 0, column: 3))
        #expect(link.url == URL(string: "https://example.com/a"))
        #expect(link.spans == [.init(row: 0, columns: 2 ..< 4)])
        #expect(view.link(atRow: 0, column: 4) == nil)
        #expect(view.link(atRow: 0, column: 0) == nil)
    }

    @Test func findsAWrappedLinkAfterWideCharacters() async throws {
        let view = try await linkView(running: "printf '中 https://example.com/abc d'")
        let link = try #require(view.link(atRow: 1, column: 2))
        #expect(link.url == URL(string: "https://example.com/abc"))
        #expect(
            link.spans == [
                .init(row: 0, columns: 3 ..< 10), .init(row: 1, columns: 0 ..< 10), .init(row: 2, columns: 0 ..< 6),
            ])
        #expect(view.link(atRow: 0, column: 0) == nil)
        #expect(view.link(atRow: 2, column: 7) == nil)
        #expect(view.link(atRow: 9, column: 0) == nil)
    }

    @Test func opensALinkWithCommandClick() async throws {
        let view = try await linkView(running: "printf 'https://example.com'")
        var actions: [TerminalContentView.LinkAction] = []
        view.performLinkAction = { actions.append($0) }
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view))
        #expect(actions.isEmpty)
        #expect(view.selection != nil)
        view.selection = nil
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view, modifierFlags: .command))
        view.mouseDown(
            with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view, modifierFlags: .command, clickCount: 2))
        view.mouseDown(
            with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view, modifierFlags: .command, clickCount: 3))
        #expect(actions == [.open(try #require(URL(string: "https://example.com")))])
        #expect(view.selection == nil)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 2, in: view, modifierFlags: .command))
        #expect(actions.count == 1)
        #expect(view.selection != nil)
        view.selection = nil
        view.mouseDown(
            with: try mouseEvent(.leftMouseDown, row: 2, column: 2, in: view, modifierFlags: .command, clickCount: 2))
        #expect(actions.count == 1)
        #expect(view.selection != nil)
        #expect(window.contentView === view)
    }

    @Test func opensNoUnsafeLink() async throws {
        let view = try await linkView(running: "printf '\\033]8;;zoommtg://join\\033\\\\join\\033]8;;\\033\\\\'")
        var actions: [TerminalContentView.LinkAction] = []
        view.performLinkAction = { actions.append($0) }
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .command))
        #expect(actions.isEmpty)
        #expect(window.contentView === view)
    }

    @Test func opensALinkWhileTheProgramTracksTheMouse() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf '\\033[?1000hhttps://a.com\\r\\n'; dd bs=1 count=12 2>/dev/null | od -An -tx1"
        )
        let view = TerminalContentView(session: session)
        var actions: [TerminalContentView.LinkAction] = []
        view.performLinkAction = { actions.append($0) }
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        await session.waitForText("https://a.com")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .command))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 1, in: view, modifierFlags: .command))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 0, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: 0, in: view))
        #expect(await session.linesAfterExit().contains("1b  5b  4d  20  21  22  1b  5b  4d  23  21  22"))
        #expect(actions.count == 1)
        #expect(window.contentView === view)
    }

    @Test func underlinesTheHoveredLink() async throws {
        let view = try await linkView(running: "printf 'https://example.com'")
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let location = view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil)
        let plain = try image(of: view)
        view.updateHoveredLink(at: location, modifierFlags: [])
        #expect(view.hoveredLink == nil)
        view.updateHoveredLink(at: location, modifierFlags: .command)
        #expect(view.hoveredLink?.url == URL(string: "https://example.com"))
        #expect(try image(of: view) != plain)
        view.mouseExited(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(NSCursor.current == .pointingHand)
        #expect(view.hoveredLink == nil)
        #expect(try image(of: view) == plain)
        #expect(window.contentView === view)
    }

    @Test func showsTheTargetOfTheHoveredHyperlink() async throws {
        let view = try await linkView(
            running: "printf '\\033]8;;https://b.com/\\033\\\\a.com\\033]8;;\\033\\\\\\nhttps://c.com'")
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let hyperlink = view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil)
        view.updateHoveredLink(at: hyperlink, modifierFlags: .command)
        #expect(view.toolTip == "https://b.com/")
        view.updateHoveredLink(
            at: view.convert(view.rect(row: 1, columns: 2 ..< 3).center, to: nil), modifierFlags: .command)
        #expect(view.hoveredLink?.url == URL(string: "https://c.com"))
        #expect(view.toolTip == nil)
        view.updateHoveredLink(at: hyperlink, modifierFlags: .command)
        #expect(view.toolTip == "https://b.com/")
        view.mouseExited(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(view.toolTip == nil)
        #expect(window.contentView === view)
    }

    @Test func keepsTheTargetUntilNewOutputChangesIt() async throws {
        let session = TerminalSession(
            running:
                "printf '\\033]8;;https://b.com/\\033\\\\a.com\\033]8;;\\033\\\\'; read x; printf '\\033[3;1Hz'; read x; printf '\\033[Hdone'"
        )
        session.resize(columns: 10, rows: 4)
        let view = TerminalContentView(session: session)
        let window = MouseWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.currentModifierFlags = { .command }
        try session.start()
        await session.waitForText("a.com")
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: .command)
        #expect(view.toolTip == "https://b.com/")
        session.send(Array("\r".utf8))
        await session.waitForText("z")
        view.display()
        #expect(view.toolTip == "https://b.com/")
        session.send(Array("\r".utf8))
        await session.waitForText("done")
        NSCursor.pointingHand.set()
        view.display()
        #expect(NSCursor.current == .iBeam)
        #expect(view.hoveredLink == nil)
        #expect(view.toolTip == nil)
        #expect(window.contentView === view)
    }

    @Test func keepsTheUnderlineDuringOutput() async throws {
        let session = TerminalSession(
            running: "printf 'https://a.com'; read x; printf '\\033[3;1Hz'; read x; printf '\\033[H\\033[2@ab'"
        )
        session.resize(columns: 20, rows: 4)
        let view = TerminalContentView(session: session)
        let window = MouseWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.currentModifierFlags = { .command }
        try session.start()
        await session.waitForText("a.com")
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 4 ..< 5).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: .command)
        session.send(Array("\r".utf8))
        await session.waitForText("z")
        view.display()
        #expect(view.hoveredLink?.spans == [.init(row: 0, columns: 0 ..< 13)])
        session.send(Array("\r".utf8))
        await session.waitForText("abhttps")
        let underlined = try image(of: view)
        #expect(view.hoveredLink?.spans == [.init(row: 0, columns: 2 ..< 15)])
        view.mouseExited(with: try mouseEvent(.mouseMoved, row: 0, column: 4, in: view))
        #expect(try image(of: view) != underlined)
        #expect(window.contentView === view)
    }

    @Test func updatesTheTargetAfterAScroll() async throws {
        let session = TerminalSession(
            running:
                "for i in $(seq 1 30); do printf '\\033]8;;https://%s.com/\\033\\\\link\\033]8;;\\033\\\\\\n' $i; done"
        )
        let scrollView = TerminalScrollView(session: session)
        let window = MouseWindow(contentView: scrollView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.currentModifierFlags = { .command }
        let row = Int((view.visibleRect.midY - TerminalContentView.padding) / view.cellSize.height)
        window.mouseLocation = view.convert(view.rect(row: row, columns: 1 ..< 2).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: .command)
        #expect(view.toolTip == "https://\(row + 1).com/")
        view.scroll(CGPoint(x: 0, y: view.visibleRect.minY - 5 * view.cellSize.height))
        #expect(view.toolTip == "https://\(row - 4).com/")
        #expect(window.contentView === scrollView)
    }

    @Test func updatesTheTargetAfterAFontChange() async throws {
        let view = try await linkView(
            running:
                "printf '\\033]8;;https://a.com/\\033\\\\a.com\\033]8;;https://b.com/\\033\\\\b.com\\033]8;;\\033\\\\'"
        )
        let window = MouseWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.currentModifierFlags = { .command }
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 7 ..< 8).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: .command)
        #expect(view.toolTip == "https://b.com/")
        view.font = .monospacedSystemFont(ofSize: 2 * view.font.pointSize, weight: .regular)
        #expect(view.toolTip == "https://a.com/")
        #expect(window.contentView === view)
    }

    @Test func clearsTheTargetAfterCommandIsReleasedInAnotherView() async throws {
        let view = try await linkView(
            running:
                "printf '\\033]8;;https://a.com/\\033\\\\a.com\\033]8;;https://b.com/\\033\\\\b.com\\033]8;;\\033\\\\'"
        )
        let window = MouseWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 7 ..< 8).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: .command)
        #expect(view.toolTip == "https://b.com/")
        view.font = .monospacedSystemFont(ofSize: 2 * view.font.pointSize, weight: .regular)
        #expect(NSCursor.current == .iBeam)
        #expect(view.hoveredLink == nil)
        #expect(view.toolTip == nil)
        #expect(window.contentView === view)
    }

    @Test func clearsTheTargetWhenCommandIsReleasedWhileAnotherViewIsFocused() async throws {
        let focusedView = try await linkView(
            running: "printf '\\033]8;;https://b.com/\\033\\\\ab\\033]8;;\\033\\\\'")
        let view = TerminalContentView(session: focusedView.session)
        let window = MouseWindow(contentView: NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100)))
        window.contentView?.addSubview(focusedView)
        window.contentView?.addSubview(view)
        focusedView.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.frame = NSRect(x: 200, y: 0, width: 200, height: 100)
        window.makeFirstResponder(focusedView)
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 1 ..< 2).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: .command)
        #expect(view.toolTip == "https://b.com/")
        NSApplication.shared.sendEvent(try flagsChanged([]))
        #expect(NSCursor.current == .iBeam)
        #expect(view.hoveredLink == nil)
        #expect(view.toolTip == nil)
        #expect(window.firstResponder === focusedView)
    }

    @Test func showsNoTargetAfterAFontChangeWithoutAHover() async throws {
        let view = try await linkView(
            running:
                "printf '\\033]8;;https://a.com/\\033\\\\a.com\\033]8;;https://b.com/\\033\\\\b.com\\033]8;;\\033\\\\'"
        )
        let window = MouseWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.currentModifierFlags = { .command }
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 7 ..< 8).center, to: nil)
        view.updateHoveredLink(at: window.mouseLocation, modifierFlags: [])
        view.font = .monospacedSystemFont(ofSize: 2 * view.font.pointSize, weight: .regular)
        #expect(view.hoveredLink == nil)
        #expect(view.toolTip == nil)
        #expect(window.contentView === view)
    }

    @Test func setsThePointerOnACursorUpdate() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        NSCursor.arrow.set()
        view.cursorUpdate(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(NSCursor.current == .iBeam)
        view.updateHoveredLink(
            at: view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil), modifierFlags: .command)
        NSCursor.arrow.set()
        view.cursorUpdate(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(NSCursor.current == .pointingHand)
        #expect(view.trackingAreas.contains { $0.options.contains(.cursorUpdate) })
    }

    @Test func showsTheIBeamAfterTheWindowResignsKey() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view, modifierFlags: .command))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        NSCursor.arrow.set()
        view.cursorUpdate(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(NSCursor.current == .iBeam)
        #expect(view.hoveredLink == nil)
    }

    @Test func showsThePointingHandOverALinkWithCommand() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view, modifierFlags: .command))
        #expect(NSCursor.current == .pointingHand)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view))
        #expect(NSCursor.current == .iBeam)
        NSCursor.arrow.set()
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 3, in: view))
        #expect(NSCursor.current == .arrow)
        #expect(window.contentView === view)
    }

    @Test func showsThePointingHandWhileCommandIsHeldOverALink() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        let window = MouseWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        window.mouseLocation = view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil)
        view.flagsChanged(with: try flagsChanged(.command))
        #expect(NSCursor.current == .pointingHand)
        view.flagsChanged(with: try flagsChanged([]))
        #expect(NSCursor.current == .iBeam)
        #expect(window.contentView === view)
    }

    @Test func showsTheIBeamAfterTheMouseCrossesAnotherView() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        let window = NSWindow(contentView: NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)))
        window.contentView?.addSubview(view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        window.contentView?.addSubview(NSView(frame: view.convert(view.rect(row: 1, columns: 5 ..< 10), to: nil)))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view, modifierFlags: .command))
        #expect(NSCursor.current == .pointingHand)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 7, in: view, modifierFlags: .command))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 4, in: view))
        #expect(NSCursor.current == .iBeam)
        #expect(window.contentView?.subviews.first === view)
    }

    @Test func keepsThePointerWhenTheMouseIsOutside() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.updateHoveredLink(
            at: view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil), modifierFlags: .command)
        #expect(view.hoveredLink != nil)
        NSCursor.arrow.set()
        view.updateHoveredLink(at: CGPoint(x: -10, y: 10), modifierFlags: .command)
        #expect(NSCursor.current == .arrow)
        #expect(view.hoveredLink == nil)
        #expect(window.contentView === view)
    }

    @Test func keepsThePointerBelowTheText() async throws {
        let view = try await linkView(running: "printf 'https://a.com'")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let window = NSWindow(contentView: scrollView)
        scrollView.documentView = view
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        view.updateHoveredLink(
            at: view.convert(view.rect(row: 0, columns: 2 ..< 3).center, to: nil), modifierFlags: .command)
        #expect(view.hoveredLink != nil)
        NSCursor.arrow.set()
        view.updateHoveredLink(at: view.convert(CGPoint(x: 10, y: 150), to: nil), modifierFlags: .command)
        #expect(NSCursor.current == .arrow)
        #expect(view.hoveredLink == nil)
        #expect(window.contentView === scrollView)
    }
}

private final class MouseWindow: NSWindow {
    var mouseLocation = CGPoint.zero

    override var mouseLocationOutsideOfEventStream: NSPoint {
        mouseLocation
    }
}

private func flagsChanged(_ modifierFlags: NSEvent.ModifierFlags) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 55
        )
    )
}

extension CGRect {
    fileprivate var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

@MainActor
private func linkView(running script: String) async throws -> TerminalContentView {
    let session = TerminalSession(running: script)
    session.resize(columns: 10, rows: 4)
    let view = TerminalContentView(session: session)
    try session.start()
    await session.waitForExit()
    return view
}

@MainActor
private func image(of view: NSView) throws -> Data {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return try #require(representation.tiffRepresentation)
}
