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

    @Test func focusesTheNewSession() throws {
        let hostingView = NSHostingView(rootView: TerminalView(session: TerminalSession(running: "exit")))
        let window = NSWindow(contentView: hostingView)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.rootView = TerminalView(session: TerminalSession(running: "exit"))
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))
        #expect(window.firstResponder === view)
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

    @Test func scrollsToTheBottomWhenYouType() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line")
        scrollView.terminalView.scroll(.zero)
        scrollView.terminalView.keyDown(with: try keyDown("\r"))
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
                .optionAsMetaKey()
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

    @Test func keepsTheFocusOfAnotherView() {
        let textView = NSTextView()
        let window = NSWindow(contentView: textView)
        window.makeFirstResponder(textView)
        textView.addSubview(TerminalContentView(session: TerminalSession(running: "exit")))
        #expect(window.firstResponder === textView)
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
