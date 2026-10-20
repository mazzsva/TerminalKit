import AppKit
import Darwin
import SwiftUI
import Synchronization
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalStartSizeTests {
    @Test func startsWithoutAViewAtTheDefaultSize() async throws {
        let session = TerminalSession(running: "stty size")
        try session.start()
        #expect(session.state == .running)
        #expect(await session.linesAfterExit().contains("24 80"))
    }

    @Test func startsAtTheSizeOfTheViewThatAppearsWithIt() async throws {
        let session = TerminalSession(running: "stty size")
        var stateOnAppear: TerminalSession.State?
        let hostingView = NSHostingView(
            rootView: TerminalView(session: session)
                .onAppear {
                    try? session.start()
                    stateOnAppear = session.state
                }
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        #expect(stateOnAppear == .idle)
        #expect(session.state == .running)
        #expect(await session.linesAfterExit().contains("\(session.terminal.rows) \(session.terminal.columns)"))
    }

    @Test func startsAtTheSizeOfAViewThatIsNotLaidOut() async throws {
        let session = TerminalSession(running: "stty size")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        try session.start()
        #expect(session.state == .idle)
        let columns = Mutex(0)
        withObservationTracking {
            _ = session.state
        } onChange: {
            columns.withLock { $0 = MainActor.assumeIsolated { session.liveTerminal.columns } }
        }
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.state == .running)
        #expect(columns.withLock { $0 } == session.terminal.columns)
        #expect(session.terminal.columns != 80)
        #expect(await session.linesAfterExit().contains("\(session.terminal.rows) \(session.terminal.columns)"))
    }

    @Test func startsWhenTheFirstFitKeepsTheDefaultSize() async throws {
        let session = TerminalSession(running: "stty size")
        let scrollView = TerminalScrollView(session: session)
        let cellSize = scrollView.terminalView.cellSize
        try session.start()
        #expect(session.state == .idle)
        scrollView.terminalView.fit(
            to: CGSize(
                width: 80 * cellSize.width + 2 * TerminalContentView.padding,
                height: 24 * cellSize.height + 2 * TerminalContentView.padding
            )
        )
        #expect(session.state == .running)
        #expect(await session.linesAfterExit().contains("24 80"))
    }

    @Test func waitsForAViewThatCanHoldTheTerminal() async throws {
        let session = TerminalSession(running: "stty size")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 20, height: 10)
        try session.start()
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.state == .idle)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.state == .running)
        #expect(await session.linesAfterExit().contains("\(session.terminal.rows) \(session.terminal.columns)"))
    }

    @Test func startsInANewViewWhenTheFirstViewIsReleased() async throws {
        let session = TerminalSession(running: "stty size")
        weak var weakView: TerminalScrollView?
        try autoreleasepool {
            let view = TerminalScrollView(session: session)
            try session.start()
            weakView = view
        }
        #expect(weakView == nil)
        #expect(session.state == .idle)
        let hostingView = NSHostingView(rootView: TerminalView(session: session))
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        #expect(session.state == .running)
        #expect(await session.linesAfterExit().contains("\(session.terminal.rows) \(session.terminal.columns)"))
    }

    @Test func startsAtOnceWhenTheViewIsAlreadyLaidOut() async throws {
        let session = TerminalSession(running: "stty size")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.state == .idle)
        try session.start()
        #expect(session.state == .running)
        #expect(await session.linesAfterExit().contains("\(session.terminal.rows) \(session.terminal.columns)"))
    }

    @Test func sendsTheInputThatArrivesBeforeTheStartInOrder() async throws {
        let session = TerminalSession(running: "read line; echo got $line")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        try session.start()
        session.send("one ")
        try session.start()
        session.paste("two\n")
        scrollView.layoutSubtreeIfNeeded()
        #expect(await session.linesAfterExit().contains("got one two"))
    }

    @Test func sendsTheInputOfAStateObserverAfterTheWaitingInput() async throws {
        let session = TerminalSession(running: "read line; echo got $line")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        try session.start()
        session.send("one ")
        withObservationTracking {
            _ = session.state
        } onChange: {
            MainActor.assumeIsolated { session.send("two\r") }
        }
        scrollView.layoutSubtreeIfNeeded()
        #expect(await session.linesAfterExit().contains("got one two"))
    }

    @Test func endsWithoutAProcessWhenItIsTerminatedBeforeTheStart() {
        let session = TerminalSession(running: "exit")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        try? session.start()
        session.terminate()
        #expect(session.state == .exited(.uncaughtSignal(SIGHUP)))
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.state == .exited(.uncaughtSignal(SIGHUP)))
    }

    @Test func terminatesTheProcessThatStartsAfterTheLayout() async throws {
        let session = TerminalSession(running: "echo ready; exec /bin/sleep 33")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        try session.start()
        scrollView.layoutSubtreeIfNeeded()
        await session.waitForText("ready")
        session.terminate()
        #expect(session.state == .running)
        await session.waitForExit()
        #expect(session.state == .exited(.uncaughtSignal(SIGHUP)))
    }

    @Test func endsWhenTheProcessCannotStartAfterTheLayout() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/missing")))
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        try? session.start()
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.state == .exited(.exit(127)))
        session.terminate()
        #expect(session.state == .exited(.exit(127)))
    }
}
