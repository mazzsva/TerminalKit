import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalKeyboardProtocolTests {
    @Test func reportsModifiedReturn() throws {
        #expect(try input(keyDown("\r")) == nil)
        #expect(try input(keyDown("\r", modifierFlags: .shift)) == "\u{1B}[13;2u")
        #expect(try input(keyDown("\r", modifierFlags: .option)) == "\u{1B}[13;3u")
        #expect(try input(keyDown("\r", modifierFlags: .control)) == "\u{1B}[13;5u")
        #expect(try input(keyDown("\r", modifierFlags: [.control, .shift])) == "\u{1B}[13;6u")
        #expect(try input(keyDown("\r", modifierFlags: .capsLock)) == nil)
        #expect(try input(keyDown("\r", modifierFlags: [.command, .shift])) == "\u{1B}[13;10u")
        #expect(try input(keyDown(NSEnterCharacter)) == nil)
        #expect(try input(keyDown(NSEnterCharacter, modifierFlags: .shift)) == "\u{1B}[13;2u")
    }

    @Test func reportsTabBackspaceAndEscape() throws {
        #expect(try input(keyDown("\t")) == nil)
        #expect(try input(keyDown(NSBackTabCharacter, modifierFlags: .shift)) == "\u{1B}[9;2u")
        #expect(try input(keyDown("\t", modifierFlags: .control)) == "\u{1B}[9;5u")
        #expect(try input(keyDown("\u{7F}")) == nil)
        #expect(try input(keyDown("\u{7F}", modifierFlags: .option)) == "\u{1B}[127;3u")
        #expect(try input(keyDown("\u{1B}")) == "\u{1B}[27u")
        #expect(try input(keyDown("\u{1B}", modifierFlags: .shift)) == "\u{1B}[27;2u")
    }

    @Test func reportsControlAndMetaKeys() throws {
        #expect(
            try input(keyDown("\u{3}", charactersIgnoringModifiers: "c", modifierFlags: .control)) == "\u{1B}[99;5u")
        for (characters, shiftedKey, keyCode) in [("\u{3}", "C", UInt16(8)), ("\u{1F}", "_", 27)] {
            let event = try keyDown(
                characters, charactersIgnoringModifiers: shiftedKey, modifierFlags: [.control, .shift], keyCode: keyCode
            )
            let key = try #require(event.characters(byApplyingModifiers: [])?.unicodeScalars.first)
            #expect(input(event) == "\u{1B}[\(key.value);6u")
        }
        #expect(
            try input(keyDown("\u{3}", charactersIgnoringModifiers: "C", modifierFlags: [.control, .capsLock]))
                == "\u{1B}[99;5u")
        #expect(try input(keyDown("\u{3}", charactersIgnoringModifiers: "\u{441}", modifierFlags: .control)) == nil)
        #expect(try input(keyDown("\u{1}", modifierFlags: .control)) == nil)
        #expect(
            try input(keyDown("\u{0}", charactersIgnoringModifiers: " ", modifierFlags: .control)) == "\u{1B}[32;5u")
        #expect(
            try input(keyDown("\u{1B}", charactersIgnoringModifiers: "[", modifierFlags: .control)) == "\u{1B}[91;5u")
        let optionA = try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option)
        #expect(input(optionA) == nil)
        #expect(input(optionA, usesOptionAsMetaKey: true) == "\u{1B}[97;3u")
        #expect(
            try input(keyDown("ˆ", charactersIgnoringModifiers: "ö", modifierFlags: .option), usesOptionAsMetaKey: true)
                == "\u{1B}[246;3u")
        #expect(try input(keyDown("a")) == nil)
        #expect(try input(keyDown("A", modifierFlags: .shift)) == nil)
        #expect(try input(keyDown("A", modifierFlags: .shift), usesOptionAsMetaKey: true) == nil)
    }

    @Test func reportsCommandKeysWithTheSuperModifier() throws {
        #expect(try input(keyDown("c", modifierFlags: .command)) == "\u{1B}[99;9u")
        #expect(try input(keyDown("C", modifierFlags: [.command, .shift], keyCode: 8)) == "\u{1B}[99;10u")
        #expect(try input(keyDown(NSLeftArrowFunctionKey, modifierFlags: .command)) == "\u{1B}[1;9D")
        #expect(try input(keyDown(NSRightArrowFunctionKey, modifierFlags: .command)) == "\u{1B}[1;9C")
        #expect(try input(keyDown(NSUpArrowFunctionKey, modifierFlags: [.command, .shift])) == "\u{1B}[1;10A")
        #expect(try input(keyDown("\u{7F}", modifierFlags: .command)) == "\u{1B}[127;9u")
        #expect(try input(keyDown("\r", modifierFlags: .command)) == "\u{1B}[13;9u")
    }

    @Test func reportsFunctionKeysWithTheControlSequenceIntroducer() throws {
        #expect(try input(keyDown(NSUpArrowFunctionKey)) == "\u{1B}[A")
        #expect(try input(keyDown(NSHomeFunctionKey)) == "\u{1B}[H")
        #expect(try input(keyDown(NSF1FunctionKey)) == "\u{1B}[P")
        #expect(try input(keyDown(NSF3FunctionKey)) == "\u{1B}[13~")
        #expect(try input(keyDown(NSF3FunctionKey, modifierFlags: .shift)) == "\u{1B}[13;2~")
        #expect(try input(keyDown(NSUpArrowFunctionKey, modifierFlags: .control)) == "\u{1B}[1;5A")
        #expect(try input(keyDown(NSPageUpFunctionKey)) == "\u{1B}[5~")
        #expect(try input(keyDown(NSF12FunctionKey)) == "\u{1B}[24~")
        #expect(try input(keyDown(NSF13FunctionKey)) == "\u{1B}[57376u")
        #expect(try input(keyDown(NSF20FunctionKey)) == "\u{1B}[57383u")
        #expect(try input(keyDown(NSF16FunctionKey, modifierFlags: .shift)) == "\u{1B}[57379;2u")
        #expect(try input(keyDown(NSHelpFunctionKey)) == "\u{1B}[2~")
        #expect(try input(keyDown(NSF21FunctionKey)) == nil)
    }

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
            running: "printf '\\033[>4;2m'; stty raw -echo; echo ready; head -c 32 | od -An -tx1")
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
        #expect(lines.contains("3b  39  37  7e  1b  5b  32  37  3b  33  3b  31  33  7e  0d  78"))
    }

    @Test func prefersTheKittyProtocolToModifyOtherKeys() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>4;1m\\033[>1u'; stty raw -echo; echo ready; head -c 7 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        #expect(await session.linesAfterExit().contains("1b  5b  31  33  3b  32  75"))
    }

    @Test func sendsShiftReturnWithTheKittyProtocol() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>1u'; stty raw -echo; echo ready; head -c 37 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown(NSRightArrowFunctionKey, modifierFlags: .option))
        view.keyDown(with: try keyDown("\u{3}", charactersIgnoringModifiers: "c", modifierFlags: .control))
        view.keyDown(with: try keyDown("\u{3}", charactersIgnoringModifiers: "\u{441}", modifierFlags: .control))
        view.keyDown(with: try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option))
        view.usesOptionAsMetaKey = true
        view.keyDown(with: try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option))
        view.keyDown(with: try keyDown("\r"))
        let lines = await session.linesAfterExit()
        #expect(lines.contains("1b  5b  31  33  3b  32  75  1b  5b  31  3b  33  44  1b  5b  31"))
        #expect(lines.contains("3b  33  43  1b  5b  39  39  3b  35  75  03  c3  a5  1b  5b  39"))
        #expect(lines.contains("37  3b  33  75  0d"))
    }

    @Test func sendsCommandKeysWithTheKittyProtocol() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>1u'; stty raw -echo; echo ready; head -c 22 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: .command))
        view.keyDown(with: try keyDown("\u{7F}", modifierFlags: .command))
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        let lines = await session.linesAfterExit()
        #expect(lines.contains("1b  5b  39  39  3b  39  75  1b  5b  31  3b  39  44  1b  5b  31"))
        #expect(lines.contains("32  37  3b  39  75  78"))
    }

    @Test func sendsCommandCWithoutASelection() async throws {
        let session = TerminalSession(
            running: "printf 'text\\033[>1u'; stty raw -echo; echo ready; head -c 8 | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        window.makeFirstResponder(view)
        let item = NSMenuItem(title: "Copy", action: #selector(view.copy(_:)), keyEquivalent: "c")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        try session.start()
        await session.waitForText("ready")
        #expect(!view.performKeyEquivalent(with: try keyDown("c", modifierFlags: .command)))
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(!view.validateMenuItem(item))
        view.copySelection(to: pasteboard)
        view.unmarkText()
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 4))
        view.copySelection(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "text")
        view.selection = nil
        #expect(view.validateMenuItem(item))
        view.copy(nil)
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  5b  39  39  3b  39  75  78"))
    }

    @Test func sendsShiftReturnInTheLiveKeyboardMode() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[?2026h\\033[>1u'; dd bs=1 count=7 2>/dev/null | od -An -tx1")
        session.synchronizedOutputTimeout = .seconds(30)
        let view = TerminalContentView(session: session)
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesDisambiguatedKeys }) where isEnabled {
            break
        }
        #expect(!session.terminal.usesDisambiguatedKeys)
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        #expect(await session.linesAfterExit().contains("1b  5b  31  33  3b  32  75"))
    }

    @Test func sendsShiftReturnInTheLiveModifyOtherKeysMode() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[?2026h\\033[>4;2m'; dd bs=1 count=10 2>/dev/null | od -An -tx1")
        session.synchronizedOutputTimeout = .seconds(30)
        let view = TerminalContentView(session: session)
        try session.start()
        for await level in Observations({ session.liveTerminal.modifyOtherKeys }) where level == 2 {
            break
        }
        #expect(session.terminal.modifyOtherKeys == 0)
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        #expect(await session.linesAfterExit().contains("1b  5b  32  37  3b  32  3b  31  33  7e"))
    }

    @Test func leavesShiftReturnToTheMarkedText() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>1u'; stty raw -echo; echo ready; head -c 2 | od -An -tx1")
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
        #expect(await session.linesAfterExit().contains("0d  78"))
    }

    @Test func sendsReturnForModifiedReturnWithoutTheKittyProtocol() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 3 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        for modifierFlags in [NSEvent.ModifierFlags.shift, .control, .option] {
            view.keyDown(with: try keyDown("\r", modifierFlags: modifierFlags))
        }
        #expect(await session.linesAfterExit().contains("0d  0d  0d"))
    }
}

private func input(_ event: NSEvent, usesOptionAsMetaKey: Bool = false) -> String? {
    event.disambiguatedInput(usesOptionAsMetaKey: usesOptionAsMetaKey).map { String(decoding: $0, as: UTF8.self) }
}

private func otherKeyInput(_ event: NSEvent, level: Int, usesOptionAsMetaKey: Bool = false) -> String? {
    event.otherKeyInput(level: level, usesOptionAsMetaKey: usesOptionAsMetaKey)
        .map { String(decoding: $0, as: UTF8.self) }
}
