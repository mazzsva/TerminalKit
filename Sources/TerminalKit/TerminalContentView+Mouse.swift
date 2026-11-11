import AppKit
import TerminalCore

extension TerminalContentView {
    override func mouseUp(with event: NSEvent) {
        autoscrollTask?.cancel()
        autoscrollTask = nil
        guard !isOpeningLink else {
            isOpeningLink = false
            return
        }
        if releasesButton(0) {
            reportMouse(event, button: 0, isRelease: true)
        } else if event.modifierFlags.contains(.option), event.clickCount == 1, let clickLocation {
            moveCursor(to: convert(event.locationInWindow, from: nil), from: clickLocation)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if pressesButton(2, for: event) {
            reportMouse(event, button: 2)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        if reportsPressedButton(2) {
            reportDrag(event, button: 34)
        } else {
            super.rightMouseDragged(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if releasesButton(2) {
            reportMouse(event, button: 2, isRelease: true)
        } else {
            super.rightMouseUp(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2, pressesButton(1, for: event) {
            reportMouse(event, button: 1)
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2, reportsPressedButton(1) {
            reportDrag(event, button: 33)
        } else {
            super.otherMouseDragged(with: event)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, releasesButton(1) {
            reportMouse(event, button: 1, isRelease: true)
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let terminal = session.liveTerminal
        let bypasses = event.modifierFlags.contains(.function)
        let lines = Int(abs(event.deltaY).rounded(.up))
        if terminal.mouseTracking != .off, !bypasses {
            for _ in 0 ..< lines {
                reportMouse(event, button: event.deltaY > 0 ? 64 : 65)
            }
        } else if terminal.isAlternateScreenActive, terminal.usesApplicationCursorKeys, !bypasses,
            !event.modifierFlags.contains(.shift)
        {
            let key = event.deltaY > 0 ? "\u{1B}OA" : "\u{1B}OB"
            session.send(Array(String(repeating: key, count: lines).utf8))
        } else {
            super.scrollWheel(with: event)
        }
    }

    func pressesButton(_ button: Int, for event: NSEvent) -> Bool {
        guard reportsMouse(for: event) else {
            reportedButtons.remove(button)
            return false
        }
        reportedButtons.insert(button)
        return true
    }

    func reportsPressedButton(_ button: Int) -> Bool {
        reportedButtons.contains(button) && session.liveTerminal.mouseTracking != .off
    }

    func releasesButton(_ button: Int) -> Bool {
        reportedButtons.remove(button) != nil && session.liveTerminal.mouseTracking != .off
    }

    func reportsMouse(for event: NSEvent) -> Bool {
        session.liveTerminal.mouseTracking != .off && !event.modifierFlags.contains(.function)
    }

    func reportMouse(_ event: NSEvent, button: Int, isRelease: Bool = false) {
        let position = mousePosition(of: event)
        let modifiers = [(NSEvent.ModifierFlags.shift, 4), (.option, 8), (.control, 16)]
            .reduce(0) { event.modifierFlags.contains($1.0) ? $0 | $1.1 : $0 }
        lastMousePosition = position
        session.send(
            session.liveTerminal.mouseReport(
                button: button | modifiers,
                column: position.column,
                row: position.row,
                isRelease: isRelease
            )
        )
    }

    func reportDrag(_ event: NSEvent, button: Int) {
        if session.liveTerminal.mouseTracking != .clicks, mousePosition(of: event) != lastMousePosition {
            reportMouse(event, button: button)
        }
    }

    func mousePosition(of event: NSEvent) -> Terminal.Position {
        let terminal = session.liveTerminal
        let location = convert(event.locationInWindow, from: nil)
        let row = Int((location.y - Self.topPadding) / cellSize.height) - terminal.scrollback.count
        let column = Int((location.x - Self.padding) / cellSize.width)
        let limit = terminal.usesSGRMouseEncoding ? Int.max : 222
        return Terminal.Position(
            row: min(max(row, 0), terminal.rows - 1, limit), column: min(max(column, 0), terminal.columns - 1, limit))
    }
}
