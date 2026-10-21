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
        #expect(try input(keyDown(NSF13FunctionKey)) == nil)
    }

    @Test func sendsShiftReturnWithTheKittyProtocol() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>1u'; stty raw -echo; echo ready; head -c 29 | od -An -tx1")
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
        #expect(lines.contains("1b  5b  31  33  3b  32  75  1b  62  1b  66  1b  5b  39  39  3b"))
        #expect(lines.contains("35  75  03  c3  a5  1b  5b  39  37  3b  33  75  0d"))
    }

    @Test func sendsCommandKeysWithTheKittyProtocol() async throws {
        let session = TerminalSession(
            running: "printf '\\033[>1u'; stty raw -echo; echo ready; head -c 14 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        view.keyDown(with: try keyDown(NSLeftArrowFunctionKey, modifierFlags: .command))
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("c", modifierFlags: .command))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  5b  39  39  3b  39  75  1b  5b  31  3b  39  44  78"))
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
