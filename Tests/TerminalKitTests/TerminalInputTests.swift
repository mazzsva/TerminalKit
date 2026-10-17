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
        #expect(try keyDown("\u{3}", modifierFlags: .control).terminalInput == [0x03])
        #expect(try keyDown("\r").terminalInput == [0x0D])
        #expect(try keyDown("\u{7F}").terminalInput == [0x7F])
    }

    @Test func ignoresKeyEquivalents() throws {
        #expect(try keyDown("c", modifierFlags: .command).terminalInput == nil)
    }

    @Test func sendsTheArrowKeys() throws {
        #expect(try keyDown(functionKey: NSUpArrowFunctionKey).terminalInput == Array("\u{1B}[A".utf8))
        #expect(try keyDown(functionKey: NSDownArrowFunctionKey).terminalInput == Array("\u{1B}[B".utf8))
        #expect(try keyDown(functionKey: NSRightArrowFunctionKey).terminalInput == Array("\u{1B}[C".utf8))
        #expect(try keyDown(functionKey: NSLeftArrowFunctionKey).terminalInput == Array("\u{1B}[D".utf8))
    }

    @Test func sendsTheNavigationKeys() throws {
        #expect(try keyDown(functionKey: NSHomeFunctionKey).terminalInput == Array("\u{1B}[H".utf8))
        #expect(try keyDown(functionKey: NSEndFunctionKey).terminalInput == Array("\u{1B}[F".utf8))
        #expect(try keyDown(functionKey: NSPageUpFunctionKey).terminalInput == Array("\u{1B}[5~".utf8))
        #expect(try keyDown(functionKey: NSPageDownFunctionKey).terminalInput == Array("\u{1B}[6~".utf8))
        #expect(try keyDown(functionKey: NSDeleteFunctionKey).terminalInput == Array("\u{1B}[3~".utf8))
    }

    @Test func ignoresFunctionKeys() throws {
        #expect(try keyDown(functionKey: NSF1FunctionKey).terminalInput == nil)
    }
}

func keyDown(_ characters: String, modifierFlags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )
    )
}

func keyDown(functionKey: Int) throws -> NSEvent {
    try keyDown(String(try #require(UnicodeScalar(functionKey))))
}
