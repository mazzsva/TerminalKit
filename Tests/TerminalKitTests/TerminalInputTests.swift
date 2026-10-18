import AppKit
import Testing

@testable import TerminalKit

@MainActor
struct TerminalInputTests {
    @Test func sendsTypedCharacters() throws {
        #expect(try keyDown("a").terminalInput() == [0x61])
        #expect(try keyDown("é").terminalInput() == [0xC3, 0xA9])
        #expect(try keyDown("\u{F8FF}").terminalInput() == Array("\u{F8FF}".utf8))
    }

    @Test func sendsControlCharacters() throws {
        #expect(
            try keyDown("\u{3}", charactersIgnoringModifiers: "c", modifierFlags: .control).terminalInput() == [0x03])
        #expect(
            try keyDown("\u{19}", charactersIgnoringModifiers: "y", modifierFlags: .control).terminalInput() == [0x19])
        #expect(try keyDown("\r").terminalInput() == [0x0D])
        #expect(try keyDown("\u{7F}").terminalInput() == [0x7F])
    }

    @Test func sendsMetaForTheOptionKey() throws {
        let optionA = try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option)
        #expect(optionA.metaInput(applicationCursorKeys: false) == [0x1B, 0x61])
        let optionShiftA = try keyDown("Å", charactersIgnoringModifiers: "A", modifierFlags: [.option, .shift])
        #expect(optionShiftA.metaInput(applicationCursorKeys: false) == [0x1B, 0x41])
    }

    @Test func movesByWordsWithOptionAndTheArrowKeys() throws {
        #expect(try keyDown(NSLeftArrowFunctionKey, modifierFlags: .option).wordMovementInput == [0x1B, 0x62])
        #expect(try keyDown(NSRightArrowFunctionKey, modifierFlags: .option).wordMovementInput == [0x1B, 0x66])
        #expect(try keyDown(NSLeftArrowFunctionKey).wordMovementInput == nil)
        #expect(try keyDown("a", modifierFlags: .option).wordMovementInput == nil)
    }

    @Test func ignoresKeyEquivalents() throws {
        #expect(try keyDown("c", modifierFlags: .command).terminalInput() == nil)
    }

    @Test func sendsTheArrowKeys() throws {
        #expect(try keyDown(NSUpArrowFunctionKey).terminalInput() == Array("\u{1B}[A".utf8))
        #expect(try keyDown(NSDownArrowFunctionKey).terminalInput() == Array("\u{1B}[B".utf8))
        #expect(try keyDown(NSRightArrowFunctionKey).terminalInput() == Array("\u{1B}[C".utf8))
        #expect(try keyDown(NSLeftArrowFunctionKey).terminalInput() == Array("\u{1B}[D".utf8))
    }

    @Test func sendsTheApplicationCursorKeys() throws {
        #expect(try keyDown(NSUpArrowFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}OA".utf8))
        #expect(
            try keyDown(NSDownArrowFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}OB".utf8))
        #expect(
            try keyDown(NSRightArrowFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}OC".utf8))
        #expect(
            try keyDown(NSLeftArrowFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}OD".utf8))
        #expect(try keyDown(NSHomeFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}OH".utf8))
        #expect(try keyDown(NSEndFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}OF".utf8))
        #expect(try keyDown(NSPageUpFunctionKey).terminalInput(applicationCursorKeys: true) == Array("\u{1B}[5~".utf8))
    }

    @Test func sendsTheNavigationKeys() throws {
        #expect(try keyDown(NSHomeFunctionKey).terminalInput() == Array("\u{1B}OH".utf8))
        #expect(try keyDown(NSEndFunctionKey).terminalInput() == Array("\u{1B}OF".utf8))
        #expect(try keyDown(NSPageUpFunctionKey).terminalInput() == Array("\u{1B}[5~".utf8))
        #expect(try keyDown(NSPageDownFunctionKey).terminalInput() == Array("\u{1B}[6~".utf8))
        #expect(try keyDown(NSDeleteFunctionKey).terminalInput() == Array("\u{1B}[3~".utf8))
    }

    @Test func sendsReturnForTheEnterKey() throws {
        #expect(try keyDown(NSEnterCharacter).terminalInput() == [0x0D])
    }

    @Test func sendsTheBackTabKey() throws {
        #expect(
            try keyDown(NSBackTabCharacter, modifierFlags: .shift).terminalInput()
                == Array("\u{1B}[Z".utf8))
    }

    @Test func sendsOnlyTheKeyAfterADeadKey() throws {
        #expect(try keyDown("'\r", charactersIgnoringModifiers: "\r").terminalInput() == [0x0D])
        #expect(try keyDown("'\t", charactersIgnoringModifiers: "\t").terminalInput() == [0x09])
        #expect(try keyDown("'\u{1B}", charactersIgnoringModifiers: "\u{1B}").terminalInput() == [0x1B])
        #expect(try keyDown("'\u{7F}", charactersIgnoringModifiers: "\u{7F}").terminalInput() == [0x7F])
    }

    @Test func ignoresFunctionKeys() throws {
        #expect(try keyDown(NSF1FunctionKey).terminalInput() == nil)
    }
}

func keyDown(
    _ characters: String,
    charactersIgnoringModifiers: String? = nil,
    modifierFlags: NSEvent.ModifierFlags = []
) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: false,
            keyCode: 0
        )
    )
}

func keyDown(_ key: Int, modifierFlags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try keyDown(String(try #require(UnicodeScalar(key))), modifierFlags: modifierFlags)
}
