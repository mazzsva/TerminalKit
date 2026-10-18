import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalPromptTests {
    private let commands = """
        for n in 1 2 3; do
            printf '\\033]133;A\\007$ command %s\\r\\n\\033]133;C\\007' $n
            seq 1 30
            printf '\\033]133;D;0\\007'
        done
        """

    @Test func scrollsToThePreviousPrompts() async throws {
        let (scrollView, session) = try await scrollView(
            running: commands + "; printf '\\033]133;A\\007$ ready'; read line")
        let view = scrollView.terminalView
        for text in ["$ command 3", "$ command 2", "$ command 1", "$ command 1"] {
            view.keyDown(with: try commandKey(NSUpArrowFunctionKey))
            #expect(topLine(of: scrollView) == text)
        }
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func scrollsThroughShortCommands() async throws {
        let short =
            "for n in 1 2 3 4 5 6 7 8 9; do printf '\\033]133;A\\007$ short %s\\r\\n\\033]133;C\\007x\\r\\n' $n; done"
        let (scrollView, session) = try await scrollView(running: commands + "; " + short + "; echo ready; read line")
        let view = scrollView.terminalView
        var lines: [String] = []
        for _ in 0 ..< 12 {
            view.keyDown(with: try commandKey(NSUpArrowFunctionKey))
            lines.append(topLine(of: scrollView))
        }
        #expect(lines.last == "$ command 1")
        #expect(lines.contains("$ command 3"))
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func scrollsToTheNextPrompts() async throws {
        let (scrollView, session) = try await scrollView(
            running: commands + "; printf '\\033]133;A\\007$ ready'; read line")
        let view = scrollView.terminalView
        view.scroll(.zero)
        for text in ["$ command 2", "$ command 3"] {
            view.keyDown(with: try commandKey(NSDownArrowFunctionKey))
            #expect(topLine(of: scrollView) == text)
        }
        view.keyDown(with: try commandKey(NSDownArrowFunctionKey))
        #expect(scrollView.contentView.bounds.maxY == view.frame.height)
        view.keyDown(with: try commandKey(NSDownArrowFunctionKey))
        #expect(scrollView.contentView.bounds.maxY == view.frame.height)
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func scrollsToThePromptOfARunningCommand() async throws {
        let (scrollView, session) = try await scrollView(
            running: commands
                + "; printf '\\033]133;A\\007$ command 4\\r\\n\\033]133;C\\007'; seq 1 40; echo ready; read line"
        )
        scrollView.terminalView.keyDown(with: try commandKey(NSUpArrowFunctionKey))
        #expect(topLine(of: scrollView) == "$ command 4")
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func staysWithoutPrompts() async throws {
        let (scrollView, session) = try await scrollView(running: "seq 1 50; echo ready; read line")
        let top = scrollView.contentView.bounds.minY
        scrollView.terminalView.keyDown(with: try commandKey(NSUpArrowFunctionKey))
        #expect(scrollView.contentView.bounds.minY == top)
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func staysOnTheAlternateScreen() async throws {
        let (scrollView, session) = try await scrollView(running: commands + "; printf '\\033[?1049hready'; read line")
        let top = scrollView.contentView.bounds.minY
        scrollView.terminalView.keyDown(with: try commandKey(NSUpArrowFunctionKey))
        #expect(scrollView.contentView.bounds.minY == top)
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func passesOtherArrowKeysWithCommandOn() async throws {
        let (scrollView, session) = try await scrollView(
            running: commands + "; printf '\\033]133;A\\007$ ready'; read line")
        let view = scrollView.terminalView
        let recorder = Recorder()
        view.nextResponder = recorder
        let top = scrollView.contentView.bounds.minY
        for modifierFlags: NSEvent.ModifierFlags in [[.shift], [.option], [.control]] {
            view.keyDown(
                with: try keyDown(
                    NSUpArrowFunctionKey, modifierFlags: [.command, .function, .numericPad, modifierFlags]))
        }
        view.keyDown(with: try commandKey(NSUpArrowFunctionKey))
        #expect(recorder.events.count == 3)
        #expect(scrollView.contentView.bounds.minY < top)
        session.send(Array("\r".utf8))
        await session.waitForExit()
    }

    @Test func sendsOtherCommandKeysOn() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey, modifierFlags: [.command, .shift]))
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey, modifierFlags: [.command]))
        view.keyDown(with: try keyDown("a"))
        #expect(await session.linesAfterExit().contains("61"))
    }
}

private final class Recorder: NSResponder {
    var events: [NSEvent] = []

    override func keyDown(with event: NSEvent) {
        events.append(event)
    }
}

@MainActor
private func commandKey(_ key: Int) throws -> NSEvent {
    try keyDown(key, modifierFlags: [.command, .numericPad, .function])
}

@MainActor
private func topLine(of scrollView: TerminalScrollView) -> String {
    let view = scrollView.terminalView
    let row = Int((scrollView.contentView.bounds.minY / view.cellSize.height).rounded())
    return String(view.line(at: row).map(view.session.terminal.character(of:))).trimmingCharacters(in: .whitespaces)
}

@MainActor
private func scrollView(running script: String, until text: String = "ready") async throws -> (
    TerminalScrollView, TerminalSession
) {
    let session = TerminalSession(running: script)
    let scrollView = TerminalScrollView(session: session)
    scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
    scrollView.layoutSubtreeIfNeeded()
    try session.start()
    await session.waitForText(text)
    scrollView.layoutSubtreeIfNeeded()
    return (scrollView, session)
}
