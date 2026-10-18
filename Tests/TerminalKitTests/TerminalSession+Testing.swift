import AppKit
import Foundation
import Testing

@testable import TerminalKit

extension TerminalSession {
    convenience init(running script: String) {
        self.init(configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script]))
    }

    var lines: [String] {
        terminal.screen.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
    }

    func waitForExit() async {
        for await state in Observations({ self.state }) where state != .running {
            return
        }
    }

    func waitForText(_ text: String) async {
        for await lines in Observations({ self.lines }) where lines.contains(where: { $0.contains(text) }) {
            return
        }
    }

    func linesAfterExit() async -> [String] {
        await waitForExit()
        return lines
    }
}

extension NSWindow {
    convenience init(contentView: NSView) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        self.contentView = contentView
    }
}

@MainActor
func mouseEvent(
    _ type: NSEvent.EventType,
    row: Int,
    column: Int,
    in view: TerminalContentView,
    modifierFlags: NSEvent.ModifierFlags = []
) throws -> NSEvent {
    let point = CGPoint(
        x: TerminalContentView.padding + CGFloat(column) * view.cellSize.width,
        y: TerminalContentView.padding + (CGFloat(row) + 0.5) * view.cellSize.height
    )
    return try #require(
        NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    )
}
