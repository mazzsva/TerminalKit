import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalLiveModeTests {
    @Test func sendsTheCursorKeysInTheLiveMode() async throws {
        let session = updatingSession(setting: "?1", reading: "dd bs=1 count=3 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesApplicationCursorKeys }) where isEnabled {
            break
        }
        #expect(!session.terminal.usesApplicationCursorKeys)
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey))
        #expect(await session.linesAfterExit().contains("1b  4f  41"))
    }

    @Test func reportsTheMouseInTheLiveMode() async throws {
        let session = updatingSession(setting: "?1000", reading: "dd bs=1 count=6 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        for await tracking in Observations({ session.liveTerminal.mouseTracking }) where tracking != .off {
            break
        }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 0, in: view))
        #expect(await session.linesAfterExit().contains("1b  5b  4d  20  21  21"))
        #expect(window.contentView === view)
    }

    @Test func reportsTheMouseInTheLiveEncoding() async throws {
        let session = updatingSession(setting: "?1000;1006", reading: "dd bs=1 count=9 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        for await tracking in Observations({ session.liveTerminal.mouseTracking }) where tracking != .off {
            break
        }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view))
        #expect(await session.linesAfterExit().contains("1b  5b  3c  30  3b  31  3b  31  4d"))
        #expect(window.contentView === view)
    }

    @Test func reportsTheDragsInTheLiveMode() async throws {
        let session = updatingSession(setting: "?1002", reading: "dd bs=1 count=12 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        for await tracking in Observations({ session.liveTerminal.mouseTracking }) where tracking == .drags {
            break
        }
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 2, in: view))
        #expect(await session.linesAfterExit().contains("1b  5b  4d  20  21  21  1b  5b  4d  40  23  21"))
        #expect(window.contentView === view)
    }

    @Test func reportsTheFocusInTheLiveMode() async throws {
        let session = updatingSession(setting: "?1004", reading: "dd bs=1 count=3 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        window.isKey = false
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesFocusReporting }) where isEnabled {
            break
        }
        window.isKey = true
        #expect(await session.linesAfterExit().contains("1b  5b  49"))
    }

    @Test func sendsTheWheelAsCursorKeysOnTheLiveAlternateScreen() async throws {
        let session = updatingSession(setting: "?1049", reading: "dd bs=1 count=3 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        for await isActive in Observations({ session.liveTerminal.isAlternateScreenActive }) where isActive {
            break
        }
        let event = try #require(
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)
                .flatMap(NSEvent.init(cgEvent:))
        )
        view.scrollWheel(with: event)
        #expect(await session.linesAfterExit().contains("1b  5b  41"))
    }
}

@MainActor
private func updatingSession(setting mode: String, reading command: String) -> TerminalSession {
    let session = TerminalSession(running: "stty raw -echo; printf '\\033[?2026h\\033[\(mode)h'; \(command)")
    session.synchronizedOutputTimeout = .seconds(30)
    return session
}
