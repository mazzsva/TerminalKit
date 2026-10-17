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
        #expect(view.session === session)
        #expect(view.frame.size == hostingView.frame.size)
        #expect(session.terminal.columns == Int((400 - 8) / view.cellSize.width))
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
        #expect(contentView(in: hostingView) === view)
        #expect(view.session === session)
        #expect(session.terminal.columns == Int((400 - 8) / view.cellSize.width))
    }
}

@MainActor
private func contentView(in view: NSView) -> TerminalContentView? {
    view as? TerminalContentView ?? view.subviews.lazy.compactMap(contentView(in:)).first
}
