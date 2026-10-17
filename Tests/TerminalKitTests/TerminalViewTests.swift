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
private func contentView(in view: NSView) -> TerminalContentView? {
    view as? TerminalContentView ?? view.subviews.lazy.compactMap(contentView(in:)).first
}
