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

    @Test(
        arguments: [
            ("/", 0x1F), ("2", 0x00), ("6", 0x1E), ("@", 0x00), ("^", 0x1E), ("?", 0x7F), ("-", 0x1F), ("_", 0x1F),
            (" ", 0x00), ("3", 0x1B), ("4", 0x1C), ("5", 0x1D), ("7", 0x1F), ("8", 0x7F), ("a", 0x01), ("z", 0x1A),
            ("A", 0x01), ("Z", 0x1A), ("[", 0x1B), ("\\", 0x1C), ("]", 0x1D),
        ] as [(String, UInt8)])
    func sendsControlKeys(key: String, byte: UInt8) throws {
        #expect(try keyDown(key, modifierFlags: .control).controlInput == [byte])
        #expect(try keyDown(key, modifierFlags: [.control, .shift]).controlInput == [byte])
        #expect(try keyDown(key, modifierFlags: [.control, .capsLock]).controlInput == [byte])
    }

    @Test func leavesOtherKeysOutOfTheControlInput() throws {
        #expect(try keyDown("/").controlInput == nil)
        #expect(try keyDown("/", modifierFlags: .shift).controlInput == nil)
        #expect(try keyDown("/", modifierFlags: [.control, .option]).controlInput == nil)
        #expect(try keyDown("/", modifierFlags: [.control, .command]).controlInput == nil)
        #expect(try keyDown("1", modifierFlags: .control).controlInput == nil)
        #expect(try keyDown("9", modifierFlags: .control).controlInput == nil)
        #expect(try keyDown("ç", modifierFlags: .control).controlInput == nil)
        #expect(try keyDown("\t", modifierFlags: .control).controlInput == nil)
        #expect(try keyDown("\r", modifierFlags: .control).controlInput == nil)
        #expect(
            try keyDown("6", charactersIgnoringModifiers: "", modifierFlags: [.control, .shift]).controlInput == nil)
        #expect(try keyDown("ab", modifierFlags: .control).controlInput == nil)
        #expect(try keyDown(NSUpArrowFunctionKey, modifierFlags: .control).controlInput == nil)
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
        #expect(try keyDown(NSLeftArrowFunctionKey, modifierFlags: [.option, .command]).wordMovementInput == nil)
        #expect(try keyDown("a", modifierFlags: .option).wordMovementInput == nil)
    }

    @Test func deletesToTheLineStartWithCommandDelete() throws {
        #expect(try keyDown("\u{7F}", modifierFlags: .command).lineDeletionInput == [0x15])
        #expect(try keyDown("\u{7F}", modifierFlags: [.command, .shift]).lineDeletionInput == [0x15])
        #expect(try keyDown("\u{7F}", modifierFlags: [.command, .capsLock]).lineDeletionInput == [0x15])
        #expect(try keyDown("\u{7F}").lineDeletionInput == nil)
        #expect(try keyDown("\u{7F}", modifierFlags: [.command, .option]).lineDeletionInput == nil)
        #expect(try keyDown("\u{7F}", modifierFlags: [.command, .control]).lineDeletionInput == nil)
        #expect(try keyDown("u", modifierFlags: .command).lineDeletionInput == nil)
    }

    @Test func ignoresKeyEquivalents() throws {
        #expect(try keyDown("c", modifierFlags: .command).terminalInput() == nil)
        #expect(try keyDown(NSLeftArrowFunctionKey, modifierFlags: .command).terminalInput() == nil)
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

    @Test func sendsTheFunctionKeys() throws {
        #expect(try keyDown(NSF1FunctionKey).terminalInput() == Array("\u{1B}OP".utf8))
        #expect(try keyDown(NSF3FunctionKey).terminalInput() == Array("\u{1B}OR".utf8))
        #expect(try keyDown(NSF4FunctionKey).terminalInput() == Array("\u{1B}OS".utf8))
        #expect(try keyDown(NSF5FunctionKey).terminalInput() == Array("\u{1B}[15~".utf8))
        #expect(try keyDown(NSF12FunctionKey).terminalInput() == Array("\u{1B}[24~".utf8))
        #expect(try keyDown(NSF13FunctionKey).terminalInput() == Array("\u{1B}[25~".utf8))
        #expect(try keyDown(NSF14FunctionKey).terminalInput() == Array("\u{1B}[26~".utf8))
        #expect(try keyDown(NSF15FunctionKey).terminalInput() == Array("\u{1B}[28~".utf8))
        #expect(try keyDown(NSF16FunctionKey).terminalInput() == Array("\u{1B}[29~".utf8))
        #expect(try keyDown(NSF17FunctionKey).terminalInput() == Array("\u{1B}[31~".utf8))
        #expect(try keyDown(NSF18FunctionKey).terminalInput() == Array("\u{1B}[32~".utf8))
        #expect(try keyDown(NSF19FunctionKey).terminalInput() == Array("\u{1B}[33~".utf8))
        #expect(try keyDown(NSF20FunctionKey).terminalInput() == Array("\u{1B}[34~".utf8))
    }

    @Test func sendsInsertForTheHelpKey() throws {
        #expect(try keyDown(NSHelpFunctionKey).terminalInput() == Array("\u{1B}[2~".utf8))
    }

    @Test func ignoresOtherFunctionKeys() throws {
        #expect(try keyDown(NSF21FunctionKey).terminalInput() == nil)
    }

    @Test func sendsTheModifiersOfSpecialKeys() throws {
        #expect(try keyDown(NSUpArrowFunctionKey, modifierFlags: .shift).terminalInput() == Array("\u{1B}[1;2A".utf8))
        #expect(
            try keyDown(NSLeftArrowFunctionKey, modifierFlags: .control).terminalInput() == Array("\u{1B}[1;5D".utf8))
        #expect(
            try keyDown(NSF1FunctionKey, modifierFlags: [.option, .shift]).terminalInput()
                == Array("\u{1B}[1;4P".utf8))
        #expect(
            try keyDown(NSPageUpFunctionKey, modifierFlags: .shift).terminalInput() == Array("\u{1B}[5;2~".utf8))
        #expect(
            try keyDown(NSF5FunctionKey, modifierFlags: [.shift, .option, .control]).terminalInput()
                == Array("\u{1B}[15;8~".utf8))
        #expect(
            try keyDown(NSF13FunctionKey, modifierFlags: .shift).terminalInput() == Array("\u{1B}[25;2~".utf8))
        #expect(
            try keyDown(NSHelpFunctionKey, modifierFlags: .control).terminalInput() == Array("\u{1B}[2;5~".utf8))
    }

    @Test func sendsModifiedCursorKeysInApplicationMode() throws {
        #expect(
            try keyDown(NSUpArrowFunctionKey, modifierFlags: .shift).terminalInput(applicationCursorKeys: true)
                == Array("\u{1B}[1;2A".utf8))
    }

    @Test func leavesSpecialKeysOutOfTheMetaInput() throws {
        #expect(
            try keyDown(NSUpArrowFunctionKey, modifierFlags: .option).metaInput(applicationCursorKeys: false) == nil)
    }
}

func keyDown(
    _ characters: String,
    charactersIgnoringModifiers: String? = nil,
    modifierFlags: NSEvent.ModifierFlags = [],
    keyCode: UInt16 = 0
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
            keyCode: keyCode
        )
    )
}

func keyDown(_ key: Int, modifierFlags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try keyDown(String(try #require(UnicodeScalar(key))), modifierFlags: modifierFlags)
}
