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
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 2, in: view, modifierFlags: .function))
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

    @Test func reportsOneMoveBeyondTheDefaultEncoding() async throws {
        let (view, session) = try await viewReading("head -c 12 | od -An -tx1", modes: "?1003h")
        view.fit(to: CGSize(width: 4000, height: 300))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 250.5, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 260.5, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 5.5, in: view))
        #expect(await session.linesAfterExit().contains("1b  5b  4d  43  ff  21  1b  5b  4d  43  26  21"))
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

    @Test func reportsNoMiddleOrRightButtonWithFn() async throws {
        let (view, session) = try await viewReading("head -c 9", modes: "?1003h\\033[?1006h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.otherMouseDown(
            with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view, modifierFlags: .function))
        view.otherMouseDragged(
            with: try otherMouseEvent(.otherMouseDragged, row: 1, column: 3, in: view, modifierFlags: .function))
        view.otherMouseUp(
            with: try otherMouseEvent(.otherMouseUp, row: 1, column: 3, in: view, modifierFlags: .function))
        let event = try mouseEvent(.rightMouseDown, row: 0, column: 1, in: view, modifierFlags: .function)
        #expect(menusOpened { view.rightMouseDown(with: event) } == 1)
        view.rightMouseDragged(
            with: try mouseEvent(.rightMouseDragged, row: 0, column: 1, in: view, modifierFlags: .function))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 1, in: view, modifierFlags: .function))
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

    @Test func selectsWithFnWhenTheProcessUsesTheMouse() async throws {
        let (view, session) = try await viewReading("head -c 1", modes: "?1000h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .function))
        view.mouseDragged(
            with: try mouseEvent(.leftMouseDragged, row: 0, column: 3, in: view, modifierFlags: .function))
        #expect(view.selection?.head.column == 3)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 6, in: view, modifierFlags: .function))
        session.send(Array("a".utf8))
        #expect(view.selection?.anchor.column == 6)
        #expect(await session.linesAfterExit().contains("a"))
    }

    @Test func extendsTheSelectionWithFnAndShiftWhenTheProcessUsesTheMouse() async throws {
        let (view, session) = try await viewReading("head -c 1", modes: "?1000h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .function))
        view.mouseDragged(
            with: try mouseEvent(.leftMouseDragged, row: 0, column: 3, in: view, modifierFlags: .function))
        view.mouseDown(
            with: try mouseEvent(.leftMouseDown, row: 0, column: 6, in: view, modifierFlags: [.function, .shift]))
        session.send(Array("a".utf8))
        #expect(view.selection?.anchor.column == 1)
        #expect(view.selection?.head.column == 6)
        #expect(await session.linesAfterExit().contains("a"))
    }

    @Test func reportsAShiftClickWhenTheProcessUsesTheMouse() async throws {
        let (view, session) = try await viewReading("head -c 9", modes: "?1000h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .shift))
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<") && $0.hasSuffix(";2;1M") })
        #expect(view.selection == nil)
    }

    @Test func sendsTheCursorKeysForTheWheelOnTheAlternateScreen() async throws {
        let (view, session) = try await viewReading("head -c 6", modes: "?1049h")
        view.scrollWheel(with: try scrollWheelEvent(lines: 0, columns: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1))
        #expect(await session.linesAfterExit().contains("E[AE[B"))
    }

    @Test func scrollsTheViewForTheWheelWithFnOrShiftOnTheAlternateScreen() async throws {
        let (view, session) = try await viewReading("head -c 3", modes: "?1049h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.scrollWheel(with: try scrollWheelEvent(lines: 1, modifierFlags: .function))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1, modifierFlags: .shift))
        view.scrollWheel(with: try scrollWheelEvent(lines: 1))
        #expect(recorder.types == [.scrollWheel, .scrollWheel])
        #expect(await session.linesAfterExit().contains("E[A"))
    }

    @Test func reportsTheWheel() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d M; printf %sM \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(lines: -1))
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<65;") && $0.hasSuffix("M") })
    }

    @Test(arguments: [(Int32(1), 66), (-1, 67)])
    func reportsHorizontalScrolling(columns: Int32, button: Int) async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d M; printf %sM \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(lines: 0, columns: columns))
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<\(button);") && $0.hasSuffix("M") })
    }

    @Test func reportsWholeColumnsOfHorizontalTrackpadScrolling() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d x; printf %sx \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(x: 20))
        view.scrollWheel(with: try scrollWheelEvent(x: 5))
        session.send(Array("x".utf8))
        let lines = await session.linesAfterExit()
        #expect(lines.contains { $0.hasPrefix("E[<66;") && $0.hasSuffix("Mx") && $0.split(separator: "E").count == 3 })
    }

    @Test func reportsBothAxesOfDiagonalTrackpadScrolling() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d x; printf %sx \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        for _ in 0 ..< 2 {
            view.scrollWheel(with: try scrollWheelEvent(x: -10, y: 16))
        }
        session.send(Array("x".utf8))
        let reports = await session.linesAfterExit().joined().split(separator: "E").dropFirst().map { $0.prefix(4) }
        #expect(reports == ["[<64", "[<67", "[<64", "[<67"])
    }

    @Test(arguments: [("", "E[D"), ("\\033[?1h", "EOD")])
    func movesTheCursorWithOption(modes: String, key: String) async throws {
        let (view, session) = try await viewTyping("printf '\(modes)$ echo hello'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 8.5, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: 8.5, in: view, modifierFlags: .option))
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().contains("$ echo hello" + String(repeating: key, count: 4) + "done"))
    }

    @Test func movesTheCursorWithOptionAcrossAWrappedRow() async throws {
        let (view, session) = try await viewTyping("printf %$(stty size | cut -d' ' -f2)s ''; printf hello")
        let column = CGFloat(session.terminal.columns) - 0.5
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: column, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: column, in: view, modifierFlags: .option))
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().contains("hello" + String(repeating: "E[D", count: 6) + "done"))
    }

    @Test func movesTheCursorWithOptionAcrossTheMiddleOfACell() async throws {
        let (view, session) = try await viewTyping("printf '$ echo hello'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 8.45, in: view, modifierFlags: .option))
        view.mouseDragged(
            with: try mouseEvent(.leftMouseDragged, row: 1, column: 8.55, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: 8.55, in: view, modifierFlags: .option))
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().contains("$ echo hello" + String(repeating: "E[D", count: 4) + "done"))
    }

    @Test func movesNoCursorWithAnOptionDrag() async throws {
        let (view, session) = try await viewTyping("printf '$ echo hello'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 8.5, in: view, modifierFlags: .option))
        view.mouseDragged(
            with: try mouseEvent(.leftMouseDragged, row: 1, column: 2.5, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: 2.5, in: view, modifierFlags: .option))
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().contains("$ echo hellodone"))
    }

    @Test(arguments: [("", 0), ("\\033[?1049h", 1)])
    func movesNoCursorWithOptionOnAnotherLineOrTheAlternateScreen(modes: String, row: Int) async throws {
        let (view, session) = try await viewTyping("printf '\(modes)$ echo hello'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: row, column: 2.5, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: row, column: 2.5, in: view, modifierFlags: .option))
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().contains("$ echo hellodone"))
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
private func viewTyping(_ prompt: String) async throws -> (TerminalContentView, TerminalSession) {
    let session = TerminalSession(
        running: "stty raw -echo; printf 'ready\\r\\n'; \(prompt); head -n 1 | tr '\\033' E")
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 400, height: 300))
    try session.start()
    await session.waitForText("hello")
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
    override func scrollWheel(with event: NSEvent) { types.append(event.type) }
}
