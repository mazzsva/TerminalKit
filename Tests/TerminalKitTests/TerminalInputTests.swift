import AppKit
import Testing

@testable import TerminalKit

@MainActor
struct TerminalInputTests {
    @Test func sendsTypedCharacters() throws {
        #expect(try keyDown("a").terminalInput == [0x61])
        #expect(try keyDown("é").terminalInput == [0xC3, 0xA9])
    }

    @Test func sendsControlCharacters() throws {
        #expect(try keyDown("\u{3}", charactersIgnoringModifiers: "c", modifierFlags: .control).terminalInput == [0x03])
        #expect(
            try keyDown("\u{19}", charactersIgnoringModifiers: "y", modifierFlags: .control).terminalInput == [0x19])
        #expect(try keyDown("\r").terminalInput == [0x0D])
        #expect(try keyDown("\u{7F}").terminalInput == [0x7F])
    }

    @Test func ignoresKeyEquivalents() throws {
        #expect(try keyDown("c", modifierFlags: .command).terminalInput == nil)
    }

    @Test func sendsTheArrowKeys() throws {
        #expect(try keyDown(NSUpArrowFunctionKey).terminalInput == Array("\u{1B}[A".utf8))
        #expect(try keyDown(NSDownArrowFunctionKey).terminalInput == Array("\u{1B}[B".utf8))
        #expect(try keyDown(NSRightArrowFunctionKey).terminalInput == Array("\u{1B}[C".utf8))
        #expect(try keyDown(NSLeftArrowFunctionKey).terminalInput == Array("\u{1B}[D".utf8))
    }

    @Test func sendsTheNavigationKeys() throws {
        #expect(try keyDown(NSHomeFunctionKey).terminalInput == Array("\u{1B}[H".utf8))
        #expect(try keyDown(NSEndFunctionKey).terminalInput == Array("\u{1B}[F".utf8))
        #expect(try keyDown(NSPageUpFunctionKey).terminalInput == Array("\u{1B}[5~".utf8))
        #expect(try keyDown(NSPageDownFunctionKey).terminalInput == Array("\u{1B}[6~".utf8))
        #expect(try keyDown(NSDeleteFunctionKey).terminalInput == Array("\u{1B}[3~".utf8))
    }

    @Test func sendsReturnForTheEnterKey() throws {
        #expect(try keyDown(NSEnterCharacter).terminalInput == [0x0D])
    }

    @Test func sendsTheBackTabKey() throws {
        #expect(
            try keyDown(NSBackTabCharacter, modifierFlags: .shift).terminalInput
                == Array("\u{1B}[Z".utf8))
    }

    @Test func ignoresFunctionKeys() throws {
        #expect(try keyDown(NSF1FunctionKey).terminalInput == nil)
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
