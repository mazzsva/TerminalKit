import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalKeyboardProtocolTests {
    @Test func reportsModifiedReturnWithModifyOtherKeys() throws {
        for level in 1 ... 2 {
            #expect(try otherKeyInput(keyDown("\r"), level: level) == nil)
            #expect(try otherKeyInput(keyDown("\r", modifierFlags: .shift), level: level) == "\u{1B}[27;2;13~")
            #expect(try otherKeyInput(keyDown("\r", modifierFlags: .control), level: level) == "\u{1B}[27;5;13~")
            #expect(
                try otherKeyInput(keyDown("\r", modifierFlags: [.control, .shift]), level: level) == "\u{1B}[27;6;13~")
            #expect(try otherKeyInput(keyDown("\r", modifierFlags: .option), level: level) == nil)
            #expect(try otherKeyInput(keyDown("\r", modifierFlags: [.command, .shift]), level: level) == nil)
            #expect(try otherKeyInput(keyDown(NSEnterCharacter, modifierFlags: .shift), level: level) == nil)
            #expect(try otherKeyInput(keyDown(NSEnterCharacter, modifierFlags: .control), level: level) == nil)
            #expect(try otherKeyInput(keyDown("\t"), level: level) == nil)
            #expect(try otherKeyInput(keyDown("\t", modifierFlags: .control), level: level) == "\u{1B}[27;5;9~")
        }
        #expect(try otherKeyInput(keyDown("\r", modifierFlags: .shift), level: 0) == nil)
        let optionReturn = try keyDown("\r", modifierFlags: .option)
        #expect(otherKeyInput(optionReturn, level: 1, usesOptionAsMetaKey: true) == nil)
        #expect(otherKeyInput(optionReturn, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;3;13~")
        let optionControlShiftReturn = try keyDown("\r", modifierFlags: [.option, .control, .shift])
        #expect(otherKeyInput(optionControlShiftReturn, level: 1, usesOptionAsMetaKey: true) == "\u{1B}[27;2;13~")
        #expect(otherKeyInput(optionControlShiftReturn, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;8;13~")
        #expect(
            try otherKeyInput(keyDown("\t", modifierFlags: [.option, .control]), level: 1, usesOptionAsMetaKey: true)
                == nil)
    }

    @Test func reportsTabBackspaceAndEscapeWithModifyOtherKeys() throws {
        let shiftTab = try keyDown(NSBackTabCharacter, modifierFlags: .shift)
        let controlShiftTab = try keyDown(NSBackTabCharacter, modifierFlags: [.control, .shift])
        let optionShiftTab = try keyDown(NSBackTabCharacter, modifierFlags: [.option, .shift])
        let shiftBackspace = try keyDown("\u{7F}", modifierFlags: .shift)
        let controlBackspace = try keyDown("\u{7F}", modifierFlags: .control)
        let controlShiftBackspace = try keyDown("\u{7F}", modifierFlags: [.control, .shift])
        let optionBackspace = try keyDown("\u{7F}", modifierFlags: .option)
        let escape = try keyDown("\u{1B}")
        let shiftEscape = try keyDown("\u{1B}", modifierFlags: .shift)
        let controlEscape = try keyDown("\u{1B}", modifierFlags: .control)
        let optionEscape = try keyDown("\u{1B}", modifierFlags: .option)
        let optionShiftEscape = try keyDown("\u{1B}", modifierFlags: [.option, .shift])
        let optionControlEscape = try keyDown("\u{1B}", modifierFlags: [.option, .control])
        for event in [shiftTab, controlShiftTab, shiftBackspace, controlShiftBackspace, escape, shiftEscape] {
            #expect(otherKeyInput(event, level: 1, usesOptionAsMetaKey: true) == nil)
        }
        #expect(otherKeyInput(controlEscape, level: 1, usesOptionAsMetaKey: true) == nil)
        #expect(otherKeyInput(optionEscape, level: 1, usesOptionAsMetaKey: true) == nil)
        #expect(otherKeyInput(optionShiftEscape, level: 1, usesOptionAsMetaKey: true) == "\u{1B}[27;2;27~")
        #expect(otherKeyInput(optionControlEscape, level: 1, usesOptionAsMetaKey: true) == "\u{1B}[27;5;27~")
        #expect(otherKeyInput(optionControlEscape, level: 1) == nil)
        #expect(otherKeyInput(shiftTab, level: 2) == nil)
        #expect(otherKeyInput(controlShiftTab, level: 2) == "\u{1B}[27;6;9~")
        #expect(otherKeyInput(optionShiftTab, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;4;9~")
        #expect(try otherKeyInput(keyDown("\u{7F}"), level: 2) == nil)
        #expect(otherKeyInput(shiftBackspace, level: 2) == "\u{1B}[27;2;127~")
        #expect(otherKeyInput(controlBackspace, level: 2) == nil)
        #expect(otherKeyInput(controlShiftBackspace, level: 2) == "\u{1B}[27;6;8~")
        #expect(otherKeyInput(optionBackspace, level: 2) == nil)
        #expect(otherKeyInput(optionBackspace, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;3;127~")
        #expect(otherKeyInput(escape, level: 2) == nil)
        #expect(otherKeyInput(shiftEscape, level: 2) == "\u{1B}[27;2;27~")
        #expect(otherKeyInput(controlEscape, level: 2) == "\u{1B}[27;5;27~")
        #expect(otherKeyInput(optionEscape, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;3;27~")
    }

    @Test func reportsControlAndMetaKeysWithModifyOtherKeys() throws {
        let controlA = try keyDown("\u{1}", charactersIgnoringModifiers: "a", modifierFlags: .control)
        let controlShiftA = try keyDown("\u{1}", charactersIgnoringModifiers: "A", modifierFlags: [.control, .shift])
        let controlSpace = try keyDown("\u{0}", charactersIgnoringModifiers: " ", modifierFlags: .control)
        let controlTwo = try keyDown("\u{0}", charactersIgnoringModifiers: "2", modifierFlags: .control)
        let controlOne = try keyDown("1", modifierFlags: .control)
        let controlQuestionMark = try keyDown("?", modifierFlags: [.control, .shift])
        let optionA = try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option)
        let optionO = try keyDown("œ", charactersIgnoringModifiers: "ò", modifierFlags: .option)
        #expect(otherKeyInput(controlA, level: 1) == nil)
        #expect(otherKeyInput(controlA, level: 2) == "\u{1B}[27;5;97~")
        #expect(otherKeyInput(controlShiftA, level: 1) == nil)
        #expect(otherKeyInput(controlShiftA, level: 2) == "\u{1B}[27;6;65~")
        #expect(otherKeyInput(controlSpace, level: 1) == nil)
        #expect(otherKeyInput(controlSpace, level: 2) == "\u{1B}[27;5;32~")
        #expect(otherKeyInput(controlTwo, level: 1) == nil)
        #expect(otherKeyInput(controlTwo, level: 2) == "\u{1B}[27;5;50~")
        #expect(
            try otherKeyInput(
                keyDown("\u{0}", charactersIgnoringModifiers: "@", modifierFlags: [.control, .shift]), level: 1) == nil)
        #expect(
            try otherKeyInput(
                keyDown("\u{0}", charactersIgnoringModifiers: " ", modifierFlags: [.control, .shift]), level: 1) == nil)
        for key in " 2345678/" {
            #expect(
                try otherKeyInput(
                    keyDown("\u{0}", charactersIgnoringModifiers: String(key), modifierFlags: .control), level: 1)
                    == nil)
        }
        #expect(
            try otherKeyInput(
                keyDown("\u{0}", charactersIgnoringModifiers: "2", modifierFlags: [.control, .option]),
                level: 1,
                usesOptionAsMetaKey: true
            ) == nil)
        #expect(otherKeyInput(controlOne, level: 1) == "\u{1B}[27;5;49~")
        #expect(otherKeyInput(controlQuestionMark, level: 1) == "\u{1B}[27;6;63~")
        #expect(
            try otherKeyInput(
                keyDown("\u{0}", charactersIgnoringModifiers: " ", modifierFlags: [.control, .shift, .option]),
                level: 1,
                usesOptionAsMetaKey: true
            ) == "\u{1B}[27;6;32~")
        #expect(otherKeyInput(optionA, level: 1, usesOptionAsMetaKey: true) == nil)
        #expect(otherKeyInput(optionA, level: 2) == nil)
        #expect(otherKeyInput(optionA, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;3;97~")
        #expect(otherKeyInput(optionO, level: 2, usesOptionAsMetaKey: true) == "\u{1B}[27;3;242~")
        for level in 1 ... 2 {
            #expect(try otherKeyInput(keyDown("a"), level: level, usesOptionAsMetaKey: true) == nil)
            #expect(try otherKeyInput(keyDown("A", modifierFlags: .shift), level: level) == nil)
            #expect(try otherKeyInput(keyDown("!", modifierFlags: .shift), level: level) == nil)
            #expect(try otherKeyInput(keyDown(" ", modifierFlags: .shift), level: level) == nil)
            #expect(try otherKeyInput(keyDown("c", modifierFlags: .command), level: level) == nil)
            #expect(try otherKeyInput(keyDown("ß", modifierFlags: .control), level: level) == "\u{1B}[27;5;223~")
            #expect(
                try otherKeyInput(
                    keyDown("\u{3}", charactersIgnoringModifiers: "\u{441}", modifierFlags: .control), level: level
                ) == nil)
        }
    }

    @Test func keepsFunctionKeysWithModifyOtherKeys() throws {
        for key in [NSUpArrowFunctionKey, NSLeftArrowFunctionKey, NSHomeFunctionKey, NSEndFunctionKey, NSF1FunctionKey]
        {
            for modifierFlags in [NSEvent.ModifierFlags(), .shift, .control, .option] {
                #expect(
                    try otherKeyInput(keyDown(key, modifierFlags: modifierFlags), level: 2, usesOptionAsMetaKey: true)
                        == nil)
            }
        }
        #expect(try otherKeyInput(keyDown(NSDeleteFunctionKey, modifierFlags: .shift), level: 2) == nil)
        #expect(try otherKeyInput(keyDown("1", modifierFlags: [.control, .numericPad]), level: 2) == nil)
    }

    @Test func sendsShiftReturnWithModifyOtherKeys() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>4;2m'; stty raw -echo; echo ready; head -c 35 | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.usesOptionAsMetaKey = true
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        view.keyDown(with: try keyDown("\u{1}", charactersIgnoringModifiers: "a", modifierFlags: .control))
        view.keyDown(with: try keyDown("\r", modifierFlags: .option))
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        let lines = await session.linesAfterExit()
        #expect(lines.contains("1b  5b  32  37  3b  32  3b  31  33  7e  1b  5b  32  37  3b  35"))
        #expect(lines.contains("3b  39  37  7e  1b  5b  32  37  3b  33  3b  31  33  7e  1b  0d"))
        #expect(lines.contains("c2  b4  78"))
    }

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

    @Test func keepsTheAlternateScreenWithCommandK() async throws {
        let session = TerminalSession(
            running: "printf 'a\\n\\033[?1049hb\\nc'; stty raw -echo; echo ready; head -c 1 >/dev/null")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("k", modifierFlags: .command))
        #expect(session.lines.prefix(2) == ["b", "cready"])
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
            (
                "\\033[>4;2m", NSCarriageReturnCharacter, .shift,
                "ed  95  9c  1b  5b  32  37  3b  32  3b  31  33  7e  78"
            ),
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

private func otherKeyInput(_ event: NSEvent, level: Int, usesOptionAsMetaKey: Bool = false) -> String? {
    event.otherKeyInput(level: level, usesOptionAsMetaKey: usesOptionAsMetaKey)
        .map { String(decoding: $0, as: UTF8.self) }
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
