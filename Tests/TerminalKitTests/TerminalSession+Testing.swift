import AppKit
import Foundation
import Testing

@testable import TerminalKit

extension TerminalSession {
    convenience init(running script: String) {
        self.init(configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script]))
    }

    var lines: [String] {
        let terminal = terminal
        return terminal.screen.map { String($0.map(terminal.character(of:))).trimmingCharacters(in: .whitespaces) }
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

final class KeyWindow: NSWindow {
    var isKey = true {
        didSet {
            NotificationCenter.default.post(
                name: isKey ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification,
                object: self
            )
        }
    }

    override var isKeyWindow: Bool {
        isKey
    }
}

@MainActor
func mouseEvent(
    _ type: NSEvent.EventType,
    row: Int,
    column: CGFloat,
    in view: TerminalContentView,
    modifierFlags: NSEvent.ModifierFlags = [],
    clickCount: Int = 1
) throws -> NSEvent {
    let point = CGPoint(
        x: TerminalContentView.padding + column * view.cellSize.width,
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
            clickCount: clickCount,
            pressure: 1
        )
    )
}

@MainActor
func scrollWheelEvent(lines: Int32, columns: Int32 = 0) throws -> NSEvent {
    let event = try #require(
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: lines, wheel2: columns, wheel3: 0)
    )
    for field in [
        CGEventField.scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
    ] {
        event.setIntegerValueField(field, value: 0)
    }
    return try #require(NSEvent(cgEvent: event))
}

@MainActor
func scrollWheelEvent(x: Int32, y: Int32 = 0) throws -> NSEvent {
    let event = try #require(
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)
    )
    return try #require(NSEvent(cgEvent: event))
}
