import AppKit
import Testing

@testable import TerminalKit

@MainActor
struct TerminalInputTests {
    @Test(arguments: ["basic", "meta", "modes basic", "modes meta"])
    func sendsTheKeysOfTerminal(recording: String) throws {
        let url = try #require(
            Bundle.module.url(forResource: "keys", withExtension: "json", subdirectory: "Recordings"))
        let recordings = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
        let cases = try #require(recordings[recording])
        #expect(cases.count > 200)
        for (name, expected) in cases {
            let parts = name.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let mode = parts.count == 3 ? parts[0] : ""
            let modes = TerminalKeyModes(
                usesOptionAsMetaKey: recording.hasSuffix("meta"),
                usesApplicationCursorKeys: mode.hasSuffix("decckm"),
                usesApplicationKeypad: mode == "keypad",
                isAlternateScreenActive: mode.hasPrefix("alt"))
            let event = try recordedKey(parts[parts.count - 2], modifiers: parts[parts.count - 1])
            let applied = event.modifierFlags.intersection([.shift, .control])
            if modes.usesOptionAsMetaKey, !applied.isEmpty, event.characters(byApplyingModifiers: applied) == "" {
                continue
            }
            #expect(hex(sent(event, modes)) == expected, "\(recording) \(name)")
        }
    }

    @Test func sendsShiftReturnOnlyForControlShiftM() throws {
        #expect(
            try keyDown("\r", charactersIgnoringModifiers: "M", modifierFlags: [.control, .shift])
                .terminalKeyInput(TerminalKeyModes()) == .bytes([0x1B, 0x0D]))
        #expect(
            try keyDown("\t", charactersIgnoringModifiers: "I", modifierFlags: [.control, .shift])
                .terminalKeyInput(TerminalKeyModes()) == .nothing)
    }

    @Test func sendsNothingForTheHelpKeyAndHigherFunctionKeys() throws {
        for key in [NSHelpFunctionKey, NSF21FunctionKey, NSF35FunctionKey] {
            #expect(try keyDown(key).terminalKeyInput(TerminalKeyModes()) == .nothing)
        }
    }

    @Test func leavesTextKeysToTheInputSystem() throws {
        #expect(try keyDown("a").terminalKeyInput(TerminalKeyModes()) == .text)
        #expect(try keyDown("", charactersIgnoringModifiers: "").terminalKeyInput(TerminalKeyModes()) == .text)
        #expect(
            try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option)
                .terminalKeyInput(TerminalKeyModes()) == .text)
    }

    @Test func scrollsForTheHomeKeysOutsideTheAlternateScreen() throws {
        let home = try keyDown(NSHomeFunctionKey)
        #expect(home.terminalKeyInput(TerminalKeyModes()) == .scroll)
        #expect(
            home.terminalKeyInput(TerminalKeyModes(isAlternateScreenActive: true)) == .bytes(Array("\u{1B}[H".utf8)))
        let shiftedHome = try keyDown(NSHomeFunctionKey, modifierFlags: .shift)
        #expect(shiftedHome.terminalKeyInput(TerminalKeyModes(isAlternateScreenActive: true)) == .scroll)
    }

    @Test func sendsOnlyMappedKeysWithCommand() throws {
        #expect(
            try keyDown(NSF1FunctionKey, modifierFlags: .command).terminalKeyInput(TerminalKeyModes())
                == .bytes(Array("\u{1B}OP".utf8)))
        #expect(
            try keyDown(NSUpArrowFunctionKey, modifierFlags: .command).terminalKeyInput(TerminalKeyModes()) == .nothing)
        #expect(try keyDown("k", modifierFlags: .command).terminalKeyInput(TerminalKeyModes()) == .nothing)
        #expect(
            try keyDown("\r", modifierFlags: [.command, .shift]).terminalKeyInput(TerminalKeyModes())
                == .bytes([0x1B, 0x0D]))
    }
}

private let keyCodes: [String: UInt16] = [
    "a": 0, "z": 6, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "7": 26, "8": 28, "9": 25, "0": 29, "-": 27, "=": 24,
    "[": 33, "]": 30, "\\": 42, ";": 41, ",": 43, ".": 47, "/": 44, "space": 49, "return": 36, "enter": 76, "tab": 48,
    "delete": 51, "escape": 53, "kp.": 65, "kp*": 67, "kp+": 69, "clear": 71, "kp/": 75, "kp-": 78, "kp=": 81,
    "kp0": 82, "kp1": 83, "kp5": 87, "kp9": 92, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
    "f16": 106, "f17": 64, "f18": 79, "f19": 80, "help": 114, "home": 115, "pageup": 116, "forwarddelete": 117,
    "end": 119, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
]

private func recordedKey(_ name: String, modifiers: String) throws -> NSEvent {
    let code = try #require(keyCodes[name], "\(name)")
    var flags: CGEventFlags = []
    for (letter, flag) in [
        ("s", CGEventFlags.maskShift), ("c", .maskControl), ("o", .maskAlternate), ("m", .maskCommand),
    ]
    where modifiers.contains(letter) {
        flags.insert(flag)
    }
    if ["left", "right", "up", "down"].contains(name) {
        flags.formUnion([.maskNumericPad, .maskSecondaryFn])
    } else if ["help", "home", "end", "pageup", "pagedown", "forwarddelete"].contains(name) || name.hasPrefix("f") {
        flags.insert(.maskSecondaryFn)
    } else if name.hasPrefix("kp") || name == "clear" || name == "enter" {
        flags.insert(.maskNumericPad)
    }
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
    event.flags = flags
    return try #require(NSEvent(cgEvent: event))
}

private func sent(_ event: NSEvent, _ modes: TerminalKeyModes) -> [UInt8] {
    switch event.terminalKeyInput(modes) {
    case .bytes(let bytes): bytes
    case .text: Array((event.characters ?? "").utf8)
    case .nothing, .scroll: []
    }
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
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
