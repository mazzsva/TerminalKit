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

    @Test func reportsADragOutsideTheViewInTheLastCell() async throws {
        let (view, session) = try await viewReading("head -c 21", modes: "?1002h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 100, column: 200, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<32;54;18M"))
    }

    @Test func reportsAMoveToAnotherCellInsideTheView() async throws {
        let (view, session) = try await viewReading("head -c 30", modes: "?1003h\\033[?1006h")
        let window = NSWindow(contentView: view)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 1, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 2, in: view, modifierFlags: .function))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: -5, in: view))
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 1, column: 3, in: view, modifierFlags: .control))
        #expect(await session.linesAfterExit().contains("E[<35;2;1ME[<35;3;2ME[<51;4;2M"))
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
        #expect(await session.linesAfterExit().contains("E[<4;2;1M"))
        #expect(view.selection == nil)
    }

    @Test func reportsADragWithFnAfterAPressWithoutFn() async throws {
        let (view, session) = try await viewReading("head -c 37", modes: "?1002h\\033[?1006h")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(
            with: try mouseEvent(.leftMouseDragged, row: 0, column: 2, in: view, modifierFlags: .function))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 2, in: view, modifierFlags: .function))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 1, in: view, modifierFlags: .function))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 2, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 1, column: 2, in: view))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, row: 1, column: 0, in: view))
        #expect(await session.linesAfterExit().contains("E[<0;2;1ME[<32;3;1ME[<0;3;1mE[<2;1;2M"))
    }

    @Test func reportsAControlClickTwiceWithoutAMenu() async throws {
        let (view, session) = try await viewReading("head -c 30", modes: "?1000h\\033[?1006h")
        let press = try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .control)
        #expect(view.menu(for: press) == nil)
        view.mouseDown(with: press)
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 1, in: view, modifierFlags: .control))
        #expect(
            view.menu(for: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .function)) != nil
        )
        #expect(await session.linesAfterExit().contains("E[<16;2;1ME[<16;2;1ME[<16;2;1m"))
    }

    @Test func keepsThePressOfEachButton() async throws {
        let (view, session) = try await viewReading("head -c 54", modes: "?1002h\\033[?1006h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.otherMouseDown(with: try otherMouseEvent(.otherMouseDown, row: 0, column: 1, in: view, buttonNumber: 3))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, row: 0, column: 1, in: view))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 1, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 1, in: view))
        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, row: 0, column: 1, in: view))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .function))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 4, in: view))
        view.rightMouseUp(with: try mouseEvent(.rightMouseUp, row: 0, column: 1, in: view))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 1, in: view))
        #expect(recorder.types == [.otherMouseDown])
        let reports = "E[<0;2;1ME[<2;2;1ME[<2;2;1mE[<0;2;1mE[<2;2;1ME[<2;2;1m"
        #expect(await session.linesAfterExit().joined().contains(reports))
    }

    @Test func showsTheMenuForAControlClickInAWindowThatIsNotKey() async throws {
        let (view, session) = try await viewReading("head -c 1", modes: "?1000h\\033[?1006h")
        let window = NSWindow(contentView: view)
        let press = try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .control)
        #expect(!window.isKeyWindow)
        #expect(view.menu(for: press) != nil)
        session.send(Array("x".utf8))
        #expect(await session.linesAfterExit().contains("x"))
    }

    @Test func scrollsTheViewForTheWheelWithFnWhenTheProcessUsesTheMouse() async throws {
        let (view, session) = try await viewReading("head -c 10", modes: "?1000h\\033[?1006h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.scrollWheel(with: try scrollWheelEvent(lines: 1, modifierFlags: .function))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1, modifierFlags: .option))
        #expect(recorder.types == [.scrollWheel])
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<73;") })
    }

    @Test func sendsTheCursorKeysForTheWheelOnTheAlternateScreen() async throws {
        let (view, session) = try await viewReading("head -c 12", modes: "?1049h\\033[?1h")
        view.scrollWheel(with: try scrollWheelEvent(lines: 0, columns: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1, modifierFlags: .control))
        view.scrollWheel(with: try scrollWheelEvent(x: 0, y: 16))
        #expect(await session.linesAfterExit().contains("EOAEOBEOAEOA"))
    }

    @Test func scrollsTheViewForTheWheelWithFnOrShiftOnTheAlternateScreen() async throws {
        let (view, session) = try await viewReading("head -c 3", modes: "?1049h\\033[?1h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.scrollWheel(with: try scrollWheelEvent(lines: 1, modifierFlags: .function))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1, modifierFlags: .shift))
        view.scrollWheel(with: try scrollWheelEvent(lines: 1))
        #expect(recorder.types == [.scrollWheel, .scrollWheel])
        #expect(await session.linesAfterExit().contains("EOA"))
    }

    @Test func scrollsTheViewForTheWheelOnTheAlternateScreenWithoutApplicationCursorKeys() async throws {
        let (view, session) = try await viewReading("head -c 1", modes: "?1049h")
        let recorder = MouseEventRecorder()
        view.nextResponder = recorder
        view.scrollWheel(with: try scrollWheelEvent(lines: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1, modifierFlags: .option))
        session.send(Array("x".utf8))
        #expect(recorder.types == [.scrollWheel, .scrollWheel])
        #expect(await session.linesAfterExit().contains("x"))
    }

    @Test func reportsTheWheel() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d M; printf %sM \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(lines: -1))
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<65;") && $0.hasSuffix("M") })
    }

    @Test func reportsNoHorizontalScrolling() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d M; printf %sM \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(lines: 0, columns: 1))
        view.scrollWheel(with: try scrollWheelEvent(lines: 0, columns: -1))
        view.scrollWheel(with: try scrollWheelEvent(lines: -1))
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("E[<65;") && $0.hasSuffix("M") })
    }

    @Test func reportsEachTrackpadEventAsWholeLines() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d x; printf %sx \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        view.scrollWheel(with: try scrollWheelEvent(x: 0, y: 4))
        view.scrollWheel(with: try scrollWheelEvent(x: 0, y: -15))
        view.scrollWheel(with: try scrollWheelEvent(x: 30, y: 0))
        session.send(Array("x".utf8))
        let reports = await session.linesAfterExit().joined().split(separator: "E").dropFirst().map { $0.prefix(4) }
        #expect(reports == ["[<64", "[<65", "[<65"])
    }

    @Test func reportsOnlyTheVerticalAxisOfDiagonalTrackpadScrolling() async throws {
        let (view, session) = try await viewReading(
            "/bin/bash -c 'read -r -d x; printf %sx \"$REPLY\"'", modes: "?1000h\\033[?1006h")
        for _ in 0 ..< 2 {
            view.scrollWheel(with: try scrollWheelEvent(x: -10, y: 16))
        }
        session.send(Array("x".utf8))
        let reports = await session.linesAfterExit().joined().split(separator: "E").dropFirst().map { $0.prefix(4) }
        #expect(reports == ["[<64", "[<64", "[<64", "[<64"])
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

    @Test(arguments: [
        ("", 0, String(repeating: "E[D", count: 10) + "E[A"),
        ("\\033[?1049h", 1, String(repeating: "E[D", count: 10) + "E[B"),
        ("", 3, String(repeating: "E[D", count: 10) + "E[BE[B"),
    ])
    func movesTheCursorWithOptionToAnotherLineOrOnTheAlternateScreen(modes: String, row: Int, keys: String)
        async throws
    {
        let (view, session) = try await viewTyping("printf '\(modes)$ echo hello'")
        let row = view.session.terminal.scrollback.count + row
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: row, column: 2.5, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: row, column: 2.5, in: view, modifierFlags: .option))
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().contains("$ echo hello" + keys + "done"))
    }

    @Test(arguments: [
        ((6, 1), "E[AE[AE[CE[CE[C"), ((2, 1), "E[DE[AE[A"), ((2, 5), "E[DE[BE[B"),
        ((10, 3), String(repeating: "E[C", count: 7)),
    ])
    func movesTheCursorWithOptionAsTerminal(target: (Int, Int), keys: String) async throws {
        let count = keys.count
        let session = TerminalSession(
            running: "stty raw -echo; printf 'abc\\r\\ndefgh\\r\\nij'; head -c \(count) | tr '\\033' E")
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 400, height: 300))
        try session.start()
        await session.waitForText("ij")
        let (column, row) = (CGFloat(target.0) - 0.5, target.1 - 1)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: row, column: column, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: row, column: column, in: view, modifierFlags: .option))
        #expect(await session.linesAfterExit().contains("ij" + keys))
    }

    @Test(arguments: [
        ("日本語ab", (3, 1), String(repeating: "E[D", count: 6)),
        ("日本語ab", (4, 1), String(repeating: "E[D", count: 5)),
        ("日本語ab\\033[1;1H", (5, 1), String(repeating: "E[C", count: 4)),
        ("日本語ab\\033[1;1H", (6, 1), String(repeating: "E[C", count: 5)),
        ("日本語ab\\033[1;1H", (8, 1), String(repeating: "E[C", count: 7)),
        ("日本語ab\\033[1;4H", (8, 1), String(repeating: "E[C", count: 4)),
        ("日本語ab\\r\\nxyz", (4, 1), "E[A"),
        ("日本語ab\\r\\nxyz", (8, 1), "E[A" + String(repeating: "E[C", count: 4)),
        ("xyz\\r\\n日本語ab\\033[1;2H", (6, 2), "E[B" + String(repeating: "E[C", count: 4)),
        ("ab日本語cd", (2, 1), String(repeating: "E[D", count: 9)),
    ])
    func movesTheCursorWithOptionOverWideCharactersAsTerminal(text: String, target: (Int, Int), keys: String)
        async throws
    {
        let (view, session) = try await viewShowing(text)
        try optionClick(view, column: target.0, row: target.1)
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().joined().contains("<" + keys + "done"))
    }

    @Test(arguments: [
        ("abc\\033[999Cz", (3, 1), "E[D", -3, ""),
        ("abc\\r\\n\\033[999Cz", (3, 1), "E[D", -3, "E[A"),
        ("abc\\033[999Cz\\r\\n\\r\\nq\\033[1;999Hz", (3, 3), "E[D", -3, "E[BE[B"),
        ("\\033[999C日\\033[1;1H", (3, 2), "E[C", 2, ""),
        ("\\033[999C日", (3, 1), "E[D", 0, ""),
    ])
    func movesTheCursorWithOptionFromTheLastColumnAsTerminal(
        text: String, target: (Int, Int), key: String, offset: Int, suffix: String
    ) async throws {
        let (view, session) = try await viewShowing(text)
        try optionClick(view, column: target.0, row: target.1)
        session.send(Array("done\n".utf8))
        let keys = String(repeating: key, count: session.terminal.columns + offset) + suffix
        #expect(await session.linesAfterExit().joined().contains("<" + keys + "done"))
    }

    @Test func movesNoCursorWithOptionOnAPendingWrap() async throws {
        let (view, session) = try await viewShowing("abc\\033[999Cz")
        try optionClick(view, column: session.terminal.columns, row: 1)
        session.send(Array("done\n".utf8))
        #expect(await session.linesAfterExit().joined().contains("<done"))
    }

    private func optionClick(_ view: TerminalContentView, column: Int, row: Int) throws {
        let (column, row) = (CGFloat(column) - 0.5, row - 1)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: row, column: column, in: view, modifierFlags: .option))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: row, column: column, in: view, modifierFlags: .option))
    }
}

@MainActor
private func viewShowing(_ text: String) async throws -> (TerminalContentView, TerminalSession) {
    let session = TerminalSession(
        running: "stty raw -echo; printf '\(text)\\033[c'; head -c 7 >/dev/null; printf '\\033]0;go\\007'; "
            + "head -n 1 | tr '\\033' E | sed 's/^/</'")
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 400, height: 300))
    try session.start()
    for await title in Observations({ session.title }) where title == "go" {
        break
    }
    return (view, session)
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
