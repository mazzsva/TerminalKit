import AppKit
import TerminalCore

extension TerminalContentView {
    override func mouseUp(with event: NSEvent) {
        guard !isOpeningLink else {
            isOpeningLink = false
            return
        }
        if reportsMouse(for: event) {
            reportMouse(event, button: 0, isRelease: true)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if reportsMouse(for: event) {
            reportMouse(event, button: 2)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        if reportsMouse(for: event) {
            reportDrag(event, button: 34)
        } else {
            super.rightMouseDragged(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if reportsMouse(for: event) {
            reportMouse(event, button: 2, isRelease: true)
        } else {
            super.rightMouseUp(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2, reportsMouse(for: event) {
            reportMouse(event, button: 1)
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2, reportsMouse(for: event) {
            reportDrag(event, button: 33)
        } else {
            super.otherMouseDragged(with: event)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, reportsMouse(for: event) {
            reportMouse(event, button: 1, isRelease: true)
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let terminal = session.liveTerminal
        guard terminal.mouseTracking != .off || terminal.isAlternateScreenActive else {
            super.scrollWheel(with: event)
            return
        }
        scrollWheelLines +=
            event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / cellSize.height : event.scrollingDeltaY
        let lines = Int(scrollWheelLines)
        scrollWheelLines -= CGFloat(lines)
        for _ in 0 ..< abs(lines) {
            if terminal.mouseTracking != .off {
                reportMouse(event, button: lines > 0 ? 64 : 65)
            } else {
                let cursorKey = terminal.usesApplicationCursorKeys ? "\u{1B}O" : "\u{1B}["
                session.send(Array((cursorKey + (lines > 0 ? "A" : "B")).utf8))
            }
        }
    }

    func reportsMouse(for event: NSEvent) -> Bool {
        session.liveTerminal.mouseTracking != .off && !event.modifierFlags.contains(.shift)
    }

    func reportMouse(_ event: NSEvent, button: Int, isRelease: Bool = false) {
        let position = mousePosition(of: event)
        let modifiers = [(NSEvent.ModifierFlags.option, 8), (.control, 16)]
            .reduce(0) { event.modifierFlags.contains($1.0) ? $0 | $1.1 : $0 }
        lastMousePosition = position
        if let report = session.liveTerminal.mouseReport(
            button: button | modifiers,
            column: position.column,
            row: position.row,
            isRelease: isRelease
        ) {
            session.send(report)
        }
    }

    func reportDrag(_ event: NSEvent, button: Int) {
        if session.liveTerminal.mouseTracking != .clicks, mousePosition(of: event) != lastMousePosition {
            reportMouse(event, button: button)
        }
    }

    func mousePosition(of event: NSEvent) -> Terminal.Position {
        let terminal = session.terminal
        let location = convert(event.locationInWindow, from: nil)
        let row = Int((location.y - Self.padding) / cellSize.height) - terminal.scrollback.count
        let column = Int((location.x - Self.padding) / cellSize.width)
        return Terminal.Position(
            row: min(max(row, 0), terminal.rows - 1), column: min(max(column, 0), terminal.columns - 1))
    }
}
