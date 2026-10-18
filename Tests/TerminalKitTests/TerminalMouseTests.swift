import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalMouseTests {
    @Test func reportsAClick() async throws {
        let (view, session) = try await viewReading("head -c 18", modes: "?1000h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 1, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<0;2;1m"))
    }

    @Test func reportsADragToAnotherCell() async throws {
        let (view, session) = try await viewReading("head -c 19", modes: "?1002h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 3, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<32;4;2M"))
    }

    @Test func reportsTheModifiers() async throws {
        let (view, session) = try await viewReading("head -c 10", modes: "?1000h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view, modifierFlags: .control))
        #expect(await session.linesAfterExit().contains("E[<16;1;1M"))
    }

    @Test func selectsWithShiftWhenTheProcessUsesTheMouse() async throws {
        let (view, session) = try await viewReading("head -c 1", modes: "?1000h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .shift))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 3, in: view, modifierFlags: .shift))
        session.send(Array("a".utf8))
        #expect(view.selection?.head.column == 3)
        #expect(await session.linesAfterExit().contains("a"))
    }

    @Test func sendsTheCursorKeysForTheWheelOnTheAlternateScreen() async throws {
        let (view, session) = try await viewReading("head -c 6", modes: "?1049h")
        view.scrollWheel(with: try scrollWheelEvent(lines: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1))
        #expect(await session.linesAfterExit().contains("E[AE[B"))
    }

    @Test func reportsTheWheel() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d M; printf %sM \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(lines: -1))
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<65;") && $0.hasSuffix("M") })
    }
}

@MainActor
private func viewReading(_ reader: String, modes: String) async throws -> (TerminalContentView, TerminalSession) {
    let session = TerminalSession(
        running: "printf '\\033[\(modes)'; stty raw -echo; echo ready; \(reader) | tr '\\033' E")
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 400, height: 300))
    try session.start()
    await session.waitForText("ready")
    return (view, session)
}

@MainActor
private func scrollWheelEvent(lines: Int32) throws -> NSEvent {
    let event = try #require(
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
    )
    return try #require(NSEvent(cgEvent: event))
}
