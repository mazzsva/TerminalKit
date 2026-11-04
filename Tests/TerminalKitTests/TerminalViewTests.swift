import AppKit
import Foundation
import SwiftUI
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalViewTests {
    @Test func showsTheSession() throws {
        let session = TerminalSession(running: "exit")
        let hostingView = NSHostingView(rootView: TerminalView(session: session))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))
        let visibleSize = try #require(view.enclosingScrollView).contentSize
        #expect(view.session === session)
        #expect(view.frame.size == visibleSize)
        #expect(session.terminal.columns == Int((visibleSize.width - 8) / view.cellSize.width))
        #expect(session.terminal.rows == Int((visibleSize.height - 8) / view.cellSize.height))
    }

    @Test func opensLinksWithTheOpenURLActionOfTheEnvironment() throws {
        var opened: [URL] = []
        let hostingView = NSHostingView(
            rootView: TerminalView(session: TerminalSession(running: "exit"))
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        opened.append(url)
                        return .handled
                    })
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))
        let url = try #require(URL(string: "https://example.com/a"))
        view.performLinkAction(.open(url))
        #expect(opened == [url])
    }

    @Test func showsANewSessionInANewView() throws {
        let hostingView = NSHostingView(rootView: TerminalView(session: TerminalSession(running: "exit")))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))

        let session = TerminalSession(running: "exit")
        hostingView.rootView = TerminalView(session: session)
        hostingView.layoutSubtreeIfNeeded()
        let newView = try #require(contentView(in: hostingView))
        let visibleSize = try #require(newView.enclosingScrollView).contentSize
        #expect(newView !== view)
        #expect(newView.session === session)
        #expect(session.terminal.columns == Int((visibleSize.width - 8) / newView.cellSize.width))
    }

    @Test func focusesTheNewSession() async throws {
        let hostingView = NSHostingView(rootView: TerminalView(session: TerminalSession(running: "exit")))
        let window = NSWindow(contentView: hostingView)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.rootView = TerminalView(session: TerminalSession(running: "exit"))
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))
        while window.firstResponder !== view {
            try Task.checkCancellation()
            await Task.yield()
        }
        #expect(window.firstResponder === view)
    }

    @Test func keepsTheFocusWhenAnotherPaneJoins() async {
        let containerView = NSView()
        let window = NSWindow(contentView: containerView)
        let focused = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(focused)
        window.makeFirstResponder(focused.terminalView)
        containerView.addSubview(TerminalScrollView(session: TerminalSession(running: "exit")))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === focused.terminalView)
    }

    @Test func keepsTheFocusWhenAnotherPaneRestarts() async throws {
        let left = TerminalSession(running: "exit")
        let hostingView = NSHostingView(
            rootView: HStack {
                TerminalView(session: left)
                TerminalView(session: TerminalSession(running: "exit"))
            })
        let window = NSWindow(contentView: hostingView)
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))
        window.makeFirstResponder(view)
        hostingView.rootView = HStack {
            TerminalView(session: left)
            TerminalView(session: TerminalSession(running: "exit"))
        }
        hostingView.layoutSubtreeIfNeeded()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === view)
    }

    @Test func keepsTheFocusWhenThePaneMovesIntoASplit() async {
        let containerView = NSView()
        let window = NSWindow(contentView: containerView)
        let focused = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(focused)
        containerView.addSubview(TerminalScrollView(session: TerminalSession(running: "exit")))
        window.makeFirstResponder(focused.terminalView)
        let splitView = NSSplitView()
        containerView.replaceSubview(focused, with: splitView)
        splitView.addSubview(focused)
        splitView.addSubview(TerminalScrollView(session: TerminalSession(running: "exit")))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === focused.terminalView)
    }

    @Test func focusesTheLastPaneWhenTheFocusedPaneLeaves() async throws {
        let containerView = NSView()
        let window = NSWindow(contentView: containerView)
        let focused = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(focused)
        containerView.addSubview(TerminalScrollView(session: TerminalSession(running: "exit")))
        window.makeFirstResponder(focused.terminalView)
        let session = TerminalSession(running: "read line; echo \"got $line\"")
        let joined = TerminalScrollView(session: session)
        joined.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        containerView.addSubview(joined)
        joined.layoutSubtreeIfNeeded()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === focused.terminalView)
        focused.removeFromSuperview()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        try #require(window.firstResponder === joined.terminalView)
        try session.start()
        window.firstResponder?.keyDown(with: try keyDown("a"))
        window.firstResponder?.keyDown(with: try keyDown("\r"))
        #expect(await session.linesAfterExit().contains("got a"))
    }

    @Test func focusesTheLastVisiblePaneWhenTheFocusedPaneLeaves() async {
        let containerView = NSView()
        let window = NSWindow(contentView: containerView)
        let focused = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(focused)
        window.makeFirstResponder(focused.terminalView)
        let visible = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(visible)
        let hidden = TerminalScrollView(session: TerminalSession(running: "exit"))
        hidden.isHidden = true
        containerView.addSubview(hidden)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === focused.terminalView)
        focused.removeFromSuperview()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === visible.terminalView)
    }

    @Test func keepsTheFocusOfTheHostWhenTheFocusedPaneLeaves() async {
        let containerView = NSView()
        let window = NSWindow(contentView: containerView)
        let sidebar = FocusableView()
        containerView.addSubview(sidebar)
        let focused = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(focused)
        window.makeFirstResponder(focused.terminalView)
        containerView.addSubview(TerminalScrollView(session: TerminalSession(running: "exit")))
        focused.removeFromSuperview()
        #expect(window.makeFirstResponder(sidebar))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === sidebar)
    }

    @Test func keepsTheFocusWhenAnotherPaneLeaves() async {
        let containerView = NSView()
        let window = NSWindow(contentView: containerView)
        let focused = TerminalScrollView(session: TerminalSession(running: "exit"))
        let other = TerminalScrollView(session: TerminalSession(running: "exit"))
        containerView.addSubview(focused)
        containerView.addSubview(other)
        window.makeFirstResponder(focused.terminalView)
        other.removeFromSuperview()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(window.firstResponder === focused.terminalView)
    }

    @Test func growsWithTheScrollback() async throws {
        let session = TerminalSession(running: "seq 1 50")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        let lineCount = session.terminal.scrollback.count + session.terminal.rows
        #expect(session.terminal.scrollback.count > 0)
        #expect(view.frame.height == CGFloat(lineCount) * view.cellSize.height + 8)
    }

    @Test func followsNewOutputAtTheBottom() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line; seq 51 100")
        session.send(Array("\r".utf8))
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
    }

    @Test func keepsThePositionWhenScrolledBack() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line; seq 51 100")
        scrollView.terminalView.scroll(.zero)
        session.send(Array("\r".utf8))
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.minY == 0)
    }

    @Test func keepsThePositionWhenOldLinesAreRemoved() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 10500; read line; seq 1 2000")
        await session.waitForText("10500")
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: 4 + 5_000 * view.cellSize.height))
        let firstLine = { session.terminal.scrollback[Int(scrollView.contentView.bounds.minY / view.cellSize.height)] }
        let line = firstLine()
        session.send(Array("\r".utf8))
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.terminal.removedScrollbackCount > 0)
        #expect(firstLine() == line)
    }

    @Test(arguments: ["", "\\033[?1049h"])
    func keepsTheBottomVisibleWhenTheWindowShrinks(mode: String) async throws {
        let (scrollView, session) = try await scrollView(
            running: "seq 1 50; printf '\(mode)ready'; read line; seq 51 100")
        await session.waitForText("ready")
        let window = NSWindow(contentView: scrollView)
        scrollView.layoutSubtreeIfNeeded()
        window.setContentSize(CGSize(width: 300, height: 200))
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
        session.send(Array("\r".utf8))
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
    }

    @Test func keepsThePositionWhenScrolledBackAndTheWindowShrinks() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50")
        await session.waitForExit()
        let window = NSWindow(contentView: scrollView)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.terminalView.scroll(CGPoint(x: 0, y: 100))
        window.setContentSize(CGSize(width: 300, height: 200))
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.minY == 100)
    }

    @Test(
        arguments: [
            (NSHomeFunctionKey, [.command, .function], -.infinity, 0),
            (NSEndFunctionKey, [.command, .function], .infinity, 0),
            (NSPageUpFunctionKey, [.command, .function], -1, 0),
            (NSPageDownFunctionKey, [.command, .function], 1, 0),
            (NSPageUpFunctionKey, [.command, .option, .function], 0, -1),
            (NSPageDownFunctionKey, [.command, .option, .function], 0, 1),
        ] as [(Int, NSEvent.ModifierFlags, CGFloat, CGFloat)])
    func scrollsTheScrollbackWithTheKeyboard(
        key: Int, modifierFlags: NSEvent.ModifierFlags, pages: CGFloat, lines: CGFloat
    ) async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 100; printf '\\033[>1u'")
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: 600))
        let visibleHeight = scrollView.contentView.bounds.height
        let position = 600 + pages * (visibleHeight - view.cellSize.height) + lines * view.cellSize.height
        view.keyDown(with: try keyDown(key, modifierFlags: modifierFlags))
        #expect(scrollView.contentView.bounds.minY == min(max(position, 0), view.frame.height - visibleHeight))
    }

    @Test(
        arguments: [
            (NSPageUpFunctionKey, [.shift, .command, .function], ""),
            (NSPageUpFunctionKey, [.control, .command, .function], ""),
            (NSHomeFunctionKey, [.option, .command, .function], ""),
            (NSEndFunctionKey, [.option, .command, .function], ""),
            (NSPageUpFunctionKey, [.command, .function], "´"),
        ] as [(Int, NSEvent.ModifierFlags, String)])
    func keepsThePositionForOtherScrollKeys(
        key: Int, modifierFlags: NSEvent.ModifierFlags, markedText: String
    ) async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 100")
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: 600))
        view.setMarkedText(
            markedText,
            selectedRange: NSRange(location: markedText.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown(key, modifierFlags: modifierFlags))
        #expect(scrollView.contentView.bounds.minY == 600)
    }

    @Test func sendsTheScrollKeysOnTheAlternateScreen() async throws {
        let session = TerminalSession(
            running: "seq 1 100; printf '\\033[?1049h\\033[>1u'; stty raw -echo; echo ready; head -c 6 | od -An -tx1")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForText("ready")
        scrollView.terminalView.keyDown(with: try keyDown(NSHomeFunctionKey, modifierFlags: [.command, .function]))
        #expect(await session.linesAfterExit().contains("1b  5b  31  3b  39  48"))
    }

    @Test(
        arguments: [
            (NSHomeFunctionKey, -.infinity),
            (NSEndFunctionKey, .infinity),
            (NSPageUpFunctionKey, -1),
            (NSPageDownFunctionKey, 1),
        ] as [(Int, CGFloat)])
    func scrollsTheScrollbackWithThePageKeys(key: Int, pages: CGFloat) async throws {
        let (scrollView, session) = try await scrollView(
            running: "seq 1 100; stty raw -echo; echo ready; head -c 1 | od -An -tx1")
        await session.waitForText("ready")
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: 600))
        let visibleHeight = scrollView.contentView.bounds.height
        let position = 600 + pages * (visibleHeight - view.cellSize.height)
        view.keyDown(with: try keyDown(key, modifierFlags: .function))
        #expect(scrollView.contentView.bounds.minY == min(max(position, 0), view.frame.height - visibleHeight))
        session.send("x")
        #expect(await session.linesAfterExit().contains("78"))
    }

    @Test(
        arguments: [
            (NSPageUpFunctionKey, [.shift, .function], "", "1b  5b  35  7e"),
            (NSPageDownFunctionKey, [.shift, .function], "", "1b  5b  36  7e"),
            (NSHomeFunctionKey, [.shift, .function], "", "1b  5b  48"),
            (NSEndFunctionKey, [.shift, .function], "", "1b  5b  46"),
            (NSPageUpFunctionKey, .function, "\\033[?1049h", "1b  5b  35  7e"),
            (NSPageDownFunctionKey, .function, "\\033[?1049h", "1b  5b  36  7e"),
            (NSHomeFunctionKey, .function, "\\033[?1049h", "1b  4f  48"),
            (NSEndFunctionKey, .function, "\\033[?1049h", "1b  4f  46"),
            (NSPageUpFunctionKey, .function, "\\033[>1u", "1b  5b  35  7e"),
            (NSPageDownFunctionKey, .function, "\\033[>1u", "1b  5b  36  7e"),
            (NSHomeFunctionKey, .function, "\\033[>1u", "1b  5b  48"),
            (NSEndFunctionKey, .function, "\\033[>1u", "1b  5b  46"),
            (NSPageUpFunctionKey, [.shift, .function], "\\033[>1u", "1b  5b  35  3b  32  7e"),
        ] as [(Int, NSEvent.ModifierFlags, String, String)])
    func sendsThePageKeysToTheProgram(
        key: Int, modifierFlags: NSEvent.ModifierFlags, mode: String, bytes: String
    ) async throws {
        let count = bytes.split(separator: " ").count
        let (scrollView, session) = try await scrollView(
            running: "seq 1 100; printf '\(mode)'; stty raw -echo; echo ready; head -c \(count) | od -An -tx1")
        await session.waitForText("ready")
        scrollView.terminalView.keyDown(with: try keyDown(key, modifierFlags: modifierFlags))
        #expect(await session.linesAfterExit().contains(bytes))
    }

    @Test func scrollsToTheBottomWhenYouType() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line")
        scrollView.terminalView.scroll(.zero)
        scrollView.terminalView.keyDown(with: try keyDown("\r"))
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
        await session.waitForExit()
    }

    @Test func hidesThePointerWhenYouType() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line")
        var hides = 0
        scrollView.terminalView.hidePointer = { hides += 1 }
        scrollView.terminalView.keyDown(with: try keyDown(NSPageUpFunctionKey, modifierFlags: [.command, .function]))
        #expect(hides == 0)
        scrollView.terminalView.keyDown(with: try keyDown("\r"))
        #expect(hides == 1)
        await session.waitForExit()
    }

    @Test func scrollsToTheBottomForCommandDelete() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line")
        scrollView.terminalView.scroll(.zero)
        scrollView.terminalView.keyDown(with: try keyDown("\u{7F}", modifierFlags: .command))
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
        scrollView.terminalView.keyDown(with: try keyDown("\r"))
        await session.waitForExit()
    }

    @Test func scrollsToTheBottomForInsertedText() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line")
        scrollView.terminalView.scroll(.zero)
        scrollView.terminalView.insertText("\r", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
        await session.waitForExit()
    }

    @Test func scrollsWhenYouSelectAboveTheView() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50")
        await session.waitForExit()
        let window = NSWindow(contentView: scrollView)
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        let top = scrollView.contentView.bounds.minY
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: CGPoint(x: 100, y: 320),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        view.mouseDragged(with: event)
        #expect(scrollView.contentView.bounds.minY < top)
    }

    @Test func hidesTheScrollIndicator() throws {
        let session = TerminalSession(running: "exit")
        let hostingView = NSHostingView(rootView: TerminalView(session: session).scrollIndicators(.automatic))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        let scrollView = try #require(contentView(in: hostingView)?.enclosingScrollView)
        #expect(scrollView.hasVerticalScroller)
        hostingView.rootView = TerminalView(session: session).scrollIndicators(.hidden)
        hostingView.layoutSubtreeIfNeeded()
        #expect(!scrollView.hasVerticalScroller)
    }

    @Test func usesTheTerminalFont() throws {
        let session = TerminalSession(running: "exit")
        let large = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        let hostingView = NSHostingView(rootView: TerminalView(session: session).terminalFont(large))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))
        let visibleWidth = try #require(view.enclosingScrollView).contentSize.width
        #expect(view.font == large)
        #expect(session.terminal.columns == Int((visibleWidth - 8) / view.cellSize.width))

        let small = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        hostingView.rootView = TerminalView(session: session).terminalFont(small)
        hostingView.layoutSubtreeIfNeeded()
        #expect(view.font == small)
        #expect(session.terminal.columns == Int((visibleWidth - 8) / view.cellSize.width))
    }

    @Test func usesTheTerminalPalette() throws {
        var palette = TerminalPalette.standard
        palette.foreground = .orange
        let hostingView = NSHostingView(
            rootView: TerminalView(session: TerminalSession(running: "exit"))
                .terminalPalette(palette)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        #expect(try #require(contentView(in: hostingView)).palette == palette)
    }

    @Test func usesOptionAsTheMetaKey() throws {
        let hostingView = NSHostingView(
            rootView: TerminalView(session: TerminalSession(running: "exit"))
                .terminalOptionAsMetaKey()
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        #expect(try #require(contentView(in: hostingView)).usesOptionAsMetaKey)
    }

    @Test func focusesTheTerminalWhenItAppears() throws {
        let window = NSWindow(
            contentView: NSHostingView(rootView: TerminalView(session: TerminalSession(running: "exit"))))
        window.contentView?.layoutSubtreeIfNeeded()
        let view = try #require(window.contentView.flatMap(contentView(in:)))
        #expect(window.firstResponder === view)
    }

    @Test func takesTheFocusFromSwiftUI() async throws {
        let sessions = [TerminalSession(running: "exit"), TerminalSession(running: "exit")]
        let hostingView = NSHostingView(rootView: FocusedPanes(sessions: sessions, focus: nil))
        let window = NSWindow(contentView: hostingView)
        hostingView.layoutSubtreeIfNeeded()
        let views = try sessions.map { session in
            try #require(contentViews(in: hostingView).first { $0.session === session })
        }
        for index in [1, 0] {
            hostingView.rootView = FocusedPanes(sessions: sessions, focus: index)
            hostingView.layoutSubtreeIfNeeded()
            while window.firstResponder !== views[index] {
                try Task.checkCancellation()
                await Task.yield()
            }
        }
    }

    @Test func keepsTheFocusOfAnotherView() {
        let textView = NSTextView()
        let window = NSWindow(contentView: textView)
        window.makeFirstResponder(textView)
        textView.addSubview(TerminalContentView(session: TerminalSession(running: "exit")))
        #expect(window.firstResponder === textView)
    }
}

private final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

private struct FocusedPanes: View {
    let sessions: [TerminalSession]
    let focus: Int?
    @FocusState private var focusedIndex: Int?

    var body: some View {
        HStack {
            ForEach(sessions.indices, id: \.self) { index in
                TerminalView(session: sessions[index])
                    .focused($focusedIndex, equals: index)
            }
        }
        .onChange(of: focus, initial: true) {
            focusedIndex = focus
        }
    }
}

@MainActor
private func scrollView(running script: String) async throws -> (TerminalScrollView, TerminalSession) {
    let session = TerminalSession(running: script)
    let scrollView = TerminalScrollView(session: session)
    scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    scrollView.layoutSubtreeIfNeeded()
    try session.start()
    for await count in Observations({ session.terminal.scrollback.count }) where count > 0 {
        break
    }
    scrollView.layoutSubtreeIfNeeded()
    return (scrollView, session)
}

@MainActor
private func contentView(in view: NSView) -> TerminalContentView? {
    view as? TerminalContentView ?? view.subviews.lazy.compactMap(contentView(in:)).first
}

@MainActor
private func contentViews(in view: NSView) -> [TerminalContentView] {
    (view as? TerminalContentView).map { [$0] } ?? view.subviews.flatMap(contentViews(in:))
}
