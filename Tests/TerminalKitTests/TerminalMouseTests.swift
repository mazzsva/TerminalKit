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

    @Test(arguments: ["?1002h", "?1003h"])
    func reportsADragToAnotherCell(mode: String) async throws {
        let (view, session) = try await viewReading("head -c 19", modes: mode + "\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 3, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<32;4;2M"))
    }

    @Test func reportsAMoveToAnotherCellInsideTheView() async throws {
        let (view, session) = try await viewReading("head -c 20", modes: "?1003h\\033[?1006h")
        let window = NSWindow(contentView: view)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 2, in: view, modifierFlags: .shift))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: -5, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 3, in: view, modifierFlags: .control))
        #expect(await session.linesAfterExit().contains("E[<35;2;1ME[<51;4;2M"))
        #expect(window.contentView === view)
    }

    @Test func reportsAMoveBackToTheLastCellAfterAnotherViewReports() async throws {
        let (view, session) = try await viewReading("head -c 30", modes: "?1003h\\033[?1006h")
        let otherView = TerminalContentView(session: session)
        otherView.fit(to: CGSize(width: 400, height: 300))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseExited(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        otherView.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: otherView))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 3, in: view))
        #expect(await session.linesAfterExit().contains("E[<35;2;1ME[<35;3;1ME[<35;2;1M"))
    }

    @Test func reportsAMoveInTheDefaultEncoding() async throws {
        let (view, session) = try await viewReading("head -c 6", modes: "?1003h")
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        #expect(await session.linesAfterExit().contains("E[MC\"!"))
    }

    @Test func reportsAMoveAndUnderlinesTheLinkWithCommand() async throws {
        let (view, session) = try await viewReading("head -c 10", modes: "?1003h\\033[?1006hhttps://example.com\\n")
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 2, in: view, modifierFlags: .command))
        #expect(view.hoveredLink?.url == URL(string: "https://example.com"))
        #expect(await session.linesAfterExit().contains("E[<35;3;1M"))
    }

    @Test func reportsNoMoveWhenTheProcessTracksDrags() async throws {
        let (view, session) = try await viewReading("head -c 9", modes: "?1002h\\033[?1006h")
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;3;1M"))
    }

    @Test func reportsADoubleClickWithoutASelection() async throws {
        let (view, session) = try await viewReading("head -c 36", modes: "?1000h\\033[?1006h")
        for clickCount in 1 ... 2 {
            view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, clickCount: clickCount))
            view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 1, in: view, clickCount: clickCount))
        }
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<0;2;1mE[<0;2;1ME[<0;2;1m"))
        #expect(view.selection == nil)
    }

    @Test func reportsNoDragWhenTheProcessTracksClicks() async throws {
        let (view, session) = try await viewReading("head -c 18", modes: "?1000h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 3, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: 3, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<0;4;2m"))
    }

    @Test func reportsTheMiddleAndRightButtons() async throws {
        let (view, session) = try await viewReading("head -c 36", modes: "?1000h\\033[?1006h")
        view.otherMouseDown(with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view))
        view.otherMouseUp(with: try otherMouseEvent(.otherMouseUp, row: 0, column: 1, in: view))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, row: 0, column: 2, in: view))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 2, in: view))
        #expect(await session.linesAfterExit().contains("E[<1;2;1ME[<1;2;1mE[<2;3;1ME[<2;3;1m"))
    }

    @Test(arguments: ["?1002h", "?1003h"])
    func reportsAMiddleAndRightDragToAnotherCell(mode: String) async throws {
        let (view, session) = try await viewReading("head -c 38", modes: mode + "\\033[?1006h")
        view.otherMouseDown(with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view))
        view.otherMouseDragged(with: try otherMouseEvent(.otherMouseDragged, row: 0, column: 1, in: view))
        view.otherMouseDragged(with: try otherMouseEvent(.otherMouseDragged, row: 1, column: 3, in: view))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, row: 1, column: 3, in: view))
        view.rightMouseDragged(with: try mouseEvent(.rightMouseDragged, row: 1, column: 3, in: view))
        view.rightMouseDragged(with: try mouseEvent(.rightMouseDragged, row: 0, column: 1, in: view))
        #expect(await session.linesAfterExit().contains("E[<1;2;1ME[<33;4;2ME[<2;4;2ME[<34;2;1M"))
    }

    @Test func reportsTheMiddleAndRightButtonsInTheDefaultEncoding() async throws {
        let (view, session) = try await viewReading("head -c 36", modes: "?1002h")
        view.otherMouseDown(with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view))
        view.otherMouseDragged(with: try otherMouseEvent(.otherMouseDragged, row: 1, column: 3, in: view))
        view.otherMouseUp(with: try otherMouseEvent(.otherMouseUp, row: 1, column: 3, in: view))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, row: 1, column: 3, in: view))
        view.rightMouseDragged(with: try mouseEvent(.rightMouseDragged, row: 0, column: 1, in: view))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 1, in: view))
        #expect(await session.linesAfterExit().contains("E[M!\"!E[MA$\"E[M#$\"E[M\"$\"E[MB\"!E[M#\"!"))
    }

    @Test func reportsNoMiddleOrRightButtonWithShift() async throws {
        let (view, session) = try await viewReading("head -c 9", modes: "?1003h\\033[?1006h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.otherMouseDown(
            with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view, modifierFlags: .shift))
        view.otherMouseDragged(
            with: try otherMouseEvent(.otherMouseDragged, row: 1, column: 3, in: view, modifierFlags: .shift))
        view.otherMouseUp(with: try otherMouseEvent(.otherMouseUp, row: 1, column: 3, in: view, modifierFlags: .shift))
        let event = try mouseEvent(.rightMouseDown, row: 0, column: 1, in: view, modifierFlags: .shift)
        #expect(menusOpened { view.rightMouseDown(with: event) } == 1)
        view.rightMouseDragged(
            with: try mouseEvent(.rightMouseDragged, row: 0, column: 1, in: view, modifierFlags: .shift))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 1, in: view, modifierFlags: .shift))
        #expect(
            recorder.types == [.otherMouseDown, .otherMouseDragged, .otherMouseUp, .rightMouseDragged, .rightMouseUp])
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;3;1M"))
    }

    @Test func reportsNoBackOrForwardButton() async throws {
        let (view, session) = try await viewReading("head -c 9", modes: "?1003h\\033[?1006h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        for buttonNumber in 3 ... 4 {
            view.otherMouseDown(
                with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view, buttonNumber: buttonNumber))
            view.otherMouseDragged(
                with: try otherMouseEvent(.otherMouseDragged, row: 1, column: 3, in: view, buttonNumber: buttonNumber))
            view.otherMouseUp(
                with: try otherMouseEvent(.otherMouseUp, row: 1, column: 3, in: view, buttonNumber: buttonNumber))
        }
        #expect(
            recorder.types == [
                .otherMouseDown, .otherMouseDragged, .otherMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp,
            ])
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;3;1M"))
    }

    @Test func sendsNoMiddleOrRightButtonWhenTheProcessDoesNotUseTheMouse() async throws {
        let (view, session) = try await viewReading("head -c 1", modes: "?1006h")
        view.otherMouseDown(with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view))
        view.otherMouseDragged(with: try otherMouseEvent(.otherMouseDragged, row: 1, column: 3, in: view))
        view.otherMouseUp(with: try otherMouseEvent(.otherMouseUp, row: 1, column: 3, in: view))
        let event = try mouseEvent(.rightMouseDown, row: 0, column: 1, in: view)
        #expect(menusOpened { view.rightMouseDown(with: event) } == 1)
        view.rightMouseDragged(with: try mouseEvent(.rightMouseDragged, row: 0, column: 1, in: view))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 1, in: view))
        session.send(Array("a".utf8))
        #expect(await session.linesAfterExit().contains("a"))
        #expect(view.selection == nil)
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
        #expect(view.selection?.head.column == 3)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 6, in: view, modifierFlags: .shift))
        session.send(Array("a".utf8))
        #expect(view.selection?.anchor.column == 6)
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
private func otherMouseEvent(
    _ type: NSEvent.EventType,
    row: Int,
    column: CGFloat,
    in view: TerminalContentView,
    modifierFlags: NSEvent.ModifierFlags = [],
    buttonNumber: Int = 2
) throws -> NSEvent {
    let event = try #require(
        try mouseEvent(type, row: row, column: column, in: view, modifierFlags: modifierFlags).cgEvent)
    event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
    return try #require(NSEvent(cgEvent: event))
}

@MainActor
private func menusOpened(by body: () -> Void) -> Int {
    nonisolated(unsafe) var menus = 0
    let observer = NotificationCenter.default.addObserver(
        forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
    ) { notification in
        menus += 1
        nonisolated(unsafe) let menu = notification.object as? NSMenu
        RunLoop.main.perform(inModes: [.eventTracking]) { menu?.cancelTrackingWithoutAnimation() }
    }
    body()
    NotificationCenter.default.removeObserver(observer)
    return menus
}

private final class MouseEventRecorder: NSResponder {
    var types: [NSEvent.EventType] = []

    override func rightMouseDragged(with event: NSEvent) { types.append(event.type) }
    override func rightMouseUp(with event: NSEvent) { types.append(event.type) }
    override func otherMouseDown(with event: NSEvent) { types.append(event.type) }
    override func otherMouseDragged(with event: NSEvent) { types.append(event.type) }
    override func otherMouseUp(with event: NSEvent) { types.append(event.type) }
}
