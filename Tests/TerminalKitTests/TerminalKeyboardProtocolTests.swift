import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalKeyboardProtocolTests {
    @Test func sendsCommandKeysAsTerminal() async throws {
        let session = TerminalSession(
            running: "printf 'text\\n'; stty raw -echo; printf ready; head -c 3 | od -An -tx1")
        let view = TerminalContentView(session: session)
        let item = NSMenuItem(title: "Copy", action: #selector(view.copy(_:)), keyEquivalent: "c")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        try session.start()
        await session.waitForText("ready")
        #expect(!view.validateMenuItem(item))
        view.copySelection(to: pasteboard)
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        view.keyDown(with: try keyDown(NSHomeFunctionKey, modifierFlags: [.command, .function]))
        view.keyDown(with: try keyDown("\r", modifierFlags: [.command, .shift]))
        view.keyDown(with: try keyDown("\u{7F}", modifierFlags: .command))
        view.keyDown(with: try keyDown("k", modifierFlags: .command))
        #expect(session.lines.first == "ready")
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains { $0.hasSuffix(" 1b  0d  78") })
    }

    @Test func clearsToStartWithCommandK() async throws {
        let session = TerminalSession(
            running: "printf 'a\\nb\\nc'; stty raw -echo; printf '\\nready'; head -c 3 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("k", modifierFlags: [.command, .option]))
        view.keyDown(with: try keyDown("k", modifierFlags: [.command, .control]))
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("k", modifierFlags: .command))
        view.unmarkText()
        #expect(session.lines.first == "a")
        view.keyDown(with: try keyDown("k", modifierFlags: .command))
        #expect(session.lines.first == "ready")
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains { $0.hasSuffix(" c2  b4  78") })
    }

    @Test func clearsToStartOnTheAlternateScreenWithCommandK() async throws {
        let session = TerminalSession(
            running: "printf 'a\\n\\033[?1049hb\\nc'; stty raw -echo; printf ready; head -c 1 >/dev/null")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("k", modifierFlags: .command))
        #expect(session.lines.prefix(2) == ["cready", ""])
        #expect(session.terminal.scrollback.isEmpty)
        session.send("x")
        await session.waitForExit()
    }

    @Test func sendsShiftReturnAsTerminalDuringMarkedText() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  0d  c2  b4  78"))
    }

    @Test(
        arguments: [
            ("", NSCarriageReturnCharacter, .shift, "ed  95  9c  1b  0d  78"),
            ("", NSCarriageReturnCharacter, [], "ed  95  9c  0d  78"),
            ("", NSLeftArrowFunctionKey, .option, "ed  95  9c  1b  62  78"),
        ] as [(String, Int, NSEvent.ModifierFlags, String)])
    func sendsTheKeyThatTheInputMethodCommitsAndPassesOn(
        mode: String, key: Int, modifierFlags: NSEvent.ModifierFlags, bytes: String
    ) async throws {
        let count = bytes.split(separator: " ").count
        let session = TerminalSession(
            running: "printf '\(mode)'; stty raw -echo; echo ready; head -c \(count) | od -An -tx1")
        let view = TerminalContentView(session: session)
        object_setClass(view.inputContext, CommittingInputContext.self)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown(key, modifierFlags: modifierFlags))
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains(bytes))
    }

    @Test(
        arguments: [
            ("", "∫", "b", .option, 11, "ed  95  9c  1b  62  78"),
            ("", "2", "2", .control, 19, "ed  95  9c  78"),
            ("", "\u{1}", "a", .control, 0, "ed  95  9c  01  78"),
            ("", "\r", "\r", .option, 36, "ed  95  9c  1b  0d  78"),
            ("", "a", "a", [], 0, "ed  95  9c  61  78"),
        ] as [(String, String, String, NSEvent.ModifierFlags, UInt16, String)])
    func sendsTheControlAndMetaKeysThatTheInputMethodCommitsAndPassesOn(
        mode: String, characters: String, charactersIgnoringModifiers: String, modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16, bytes: String
    ) async throws {
        let count = bytes.split(separator: " ").count
        let session = TerminalSession(
            running: "printf '\(mode)'; stty raw -echo; echo ready; head -c \(count) | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.usesOptionAsMetaKey = true
        object_setClass(view.inputContext, CommittingInputContext.self)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let event = try keyDown(
            characters, charactersIgnoringModifiers: charactersIgnoringModifiers, modifierFlags: modifierFlags,
            keyCode: keyCode
        )
        view.keyDown(with: event)
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains(bytes))
    }

    @Test(
        arguments: [
            ("", "\u{1B}", "\u{1B}", [], 53, false),
            ("", "\r", "\r", .shift, 36, false),
            ("", "\r", "m", .control, 46, false),
            ("", "\n", "j", .control, 38, true),
            ("", "∫", "b", .option, 11, true),
        ] as [(String, String, String, NSEvent.ModifierFlags, UInt16, Bool)])
    func leavesTheKeyThatTheInputMethodCommitsAndConsumes(
        mode: String, characters: String, charactersIgnoringModifiers: String, modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16, unmarks: Bool
    ) async throws {
        let session = TerminalSession(
            running: "printf '\(mode)'; stty raw -echo; echo ready; head -c 4 | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.usesOptionAsMetaKey = true
        object_setClass(view.inputContext, unmarks ? UnmarkingInputContext.self : ConsumingInputContext.self)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let event = try keyDown(
            characters, charactersIgnoringModifiers: charactersIgnoringModifiers, modifierFlags: modifierFlags,
            keyCode: keyCode
        )
        view.keyDown(with: event)
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("ed  95  9c  78"))
    }

    @Test func sendsTheReturnKeysOfTerminal() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 3 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        for modifierFlags in [NSEvent.ModifierFlags.shift, .control, .option] {
            view.keyDown(with: try keyDown("\r", modifierFlags: modifierFlags))
        }
        #expect(await session.linesAfterExit().contains("1b  0d  0d"))
    }
}

private final class CommittingInputContext: NSTextInputContext {
    override func handleEvent(_ event: NSEvent) -> Bool {
        if client.hasMarkedText() {
            client.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        return super.handleEvent(event)
    }
}

private final class ConsumingInputContext: NSTextInputContext {
    override func handleEvent(_ event: NSEvent) -> Bool {
        guard client.hasMarkedText() else {
            return super.handleEvent(event)
        }
        client.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }
}

private final class UnmarkingInputContext: NSTextInputContext {
    override func handleEvent(_ event: NSEvent) -> Bool {
        guard client.hasMarkedText() else {
            return super.handleEvent(event)
        }
        client.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        client.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }
}
