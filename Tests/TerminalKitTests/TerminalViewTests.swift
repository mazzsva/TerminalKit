import AppKit
import Foundation
import SwiftUI
import Testing

@testable import TerminalKit

@MainActor
struct TerminalViewTests {
    @Test func showsTheSession() throws {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
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

    @Test func showsANewSessionInTheSameView() throws {
        let hostingView = NSHostingView(
            rootView: TerminalView(
                session: TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh"))))
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        let view = try #require(contentView(in: hostingView))

        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        hostingView.rootView = TerminalView(session: session)
        hostingView.layoutSubtreeIfNeeded()
        let visibleSize = try #require(view.enclosingScrollView).contentSize
        #expect(contentView(in: hostingView) === view)
        #expect(view.session === session)
        #expect(session.terminal.columns == Int((visibleSize.width - 8) / view.cellSize.width))
    }

    @Test func growsWithTheScrollback() async throws {
        let session = TerminalSession(
            configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "seq 1 50"])
        )
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        for await state in Observations({ session.state }) where state != .running {
            break
        }
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        let lineCount = session.terminal.scrollback.count + session.terminal.rows
        #expect(session.terminal.scrollback.count > 0)
        #expect(view.frame.height == CGFloat(lineCount) * view.cellSize.height + 8)
    }

    @Test func followsNewOutputAtTheBottom() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line; seq 51 100")
        session.send(Array("\r".utf8))
        await waitForExit(of: session)
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
    }

    @Test func keepsThePositionWhenScrolledBack() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line; seq 51 100")
        scrollView.terminalView.scroll(.zero)
        session.send(Array("\r".utf8))
        await waitForExit(of: session)
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.contentView.bounds.minY == 0)
    }

    @Test func keepsThePositionWhenOldLinesAreRemoved() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 10500; read line; seq 1 2000")
        for await lines in Observations({ session.terminal.screen.map { String($0.map(\.character)) } })
        where lines.contains(where: { $0.hasPrefix("10500") }) {
            break
        }
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: 4 + 5_000 * view.cellSize.height))
        let firstLine = { session.terminal.scrollback[Int(scrollView.contentView.bounds.minY / view.cellSize.height)] }
        let line = firstLine()
        session.send(Array("\r".utf8))
        await waitForExit(of: session)
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.terminal.removedScrollbackCount > 0)
        #expect(firstLine() == line)
    }

    @Test func scrollsToTheBottomWhenYouType() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; read line")
        scrollView.terminalView.scroll(.zero)
        scrollView.terminalView.keyDown(with: try keyDown("\r"))
        #expect(scrollView.contentView.bounds.maxY == scrollView.terminalView.frame.height)
        await waitForExit(of: session)
    }

    @Test func focusesTheTerminalWhenItAppears() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        window.contentView = NSHostingView(
            rootView: TerminalView(
                session: TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh"))))
        )
        window.contentView?.layoutSubtreeIfNeeded()
        let view = try #require(window.contentView.flatMap(contentView(in:)))
        #expect(window.firstResponder === view)
    }

    @Test func keepsTheFocusOfAnotherView() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        let textView = NSTextView()
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.addSubview(
            TerminalContentView(session: TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh"))))
        )
        #expect(window.firstResponder === textView)
    }
}

@MainActor
private func scrollView(running script: String) async throws -> (TerminalScrollView, TerminalSession) {
    let session = TerminalSession(
        configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script])
    )
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
private func waitForExit(of session: TerminalSession) async {
    for await state in Observations({ session.state }) where state != .running {
        break
    }
}

@MainActor
private func contentView(in view: NSView) -> TerminalContentView? {
    view as? TerminalContentView ?? view.subviews.lazy.compactMap(contentView(in:)).first
}
