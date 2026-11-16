import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(3)))
struct TerminalTextInputTests {
    private let noRange = NSRange(location: NSNotFound, length: 0)

    @Test func reportsNoMarkedRangeWithoutMarkedText() {
        let view = TerminalContentView(session: idleSession())
        #expect(view.markedRange().location == NSNotFound)
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        #expect(view.markedRange() == NSRange(location: 0, length: 1))
    }

    @Test func countsRangesInUTF16Units() {
        let view = TerminalContentView(session: idleSession())
        view.setMarkedText("𠮷", selectedRange: NSRange(location: 2, length: 0), replacementRange: noRange)
        #expect(view.markedRange() == NSRange(location: 0, length: 2))
        view.unmarkText()
        view.insertText("𠮷", replacementRange: noRange)
        #expect(view.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func acceptsAttributedTextFromTheInputSystem() async throws {
        let session = TerminalSession(running: "read line; echo \"got $line\"")
        let view = TerminalContentView(session: session)
        try session.start()
        view.insertText(NSAttributedString(string: "é"), replacementRange: noRange)
        view.keyDown(with: try keyDown("\r"))
        #expect(await session.linesAfterExit().contains("got é"))
    }

    @Test func reportsTheRangeOfTheSubstring() {
        let view = TerminalContentView(session: idleSession())
        view.insertText("ab", replacementRange: noRange)
        var actual = NSRange(location: NSNotFound, length: 0)
        let range = NSRange(location: 1, length: 1)
        let substring = view.attributedSubstring(forProposedRange: range, actualRange: &actual)
        #expect(substring?.string == "b")
        #expect(actual == NSRange(location: 1, length: 1))
    }

    @Test func keepsTheTextOutsideTheReplacedRange() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 3 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.insertText("ab", replacementRange: noRange)
        view.insertText("x", replacementRange: NSRange(location: 0, length: 1))
        #expect(await session.linesAfterExit().contains("61  62  78"))
    }

    @Test func deletesOneCharacterForEachReplacedCharacter() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.insertText("é", replacementRange: noRange)
        view.insertText("ê", replacementRange: NSRange(location: 0, length: 1))
        #expect(await session.linesAfterExit().contains("c3  a9  7f  c3  aa"))
    }

    @Test func ignoresTheEarlierKeyForTextFromTheInputSystem() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 4 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option))
        view.usesOptionAsMetaKey = true
        view.insertText("å", replacementRange: noRange)
        #expect(await session.linesAfterExit().contains("c3  a5  c3  a5"))
    }

    @Test func sendsAKeyWithTwoCommandsOnceDuringMarkedText() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 7 | od -An -tx1")
        let view = TerminalContentView(session: session)
        object_setClass(view.inputContext, RepeatingCommandContext.self)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  5b  41  e3  81  8b  78"))
    }

    @Test func forgetsTheInsertedTextAfterAKeyThatTheInputMethodPassesOn() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 6 | od -An -tx1")
        let view = TerminalContentView(session: session)
        object_setClass(view.inputContext, UnmarkingPassingInputContext.self)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        view.keyDown(with: try keyDown("\r", modifierFlags: .shift))
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("ed  95  9c  1b  0d  78"))
    }

    @Test func forgetsTheInsertedTextAfterAPaste() {
        let view = TerminalContentView(session: idleSession())
        view.insertText("e", replacementRange: noRange)
        view.paste(text: "abc")
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
        #expect(view.attributedSubstring(forProposedRange: NSRange(location: 0, length: 1), actualRange: nil) == nil)
    }

    @Test func forgetsTheInsertedTextAfterAClick() throws {
        let view = TerminalContentView(session: idleSession())
        view.insertText("e", replacementRange: noRange)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func leavesTheNumLockKeyToTheMarkedText() throws {
        let view = TerminalContentView(session: idleSession())
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        view.keyDown(with: try keyDown(NSClearLineFunctionKey, modifierFlags: .numericPad))
        #expect(!view.isNumLockOn)
        view.unmarkText()
        view.keyDown(with: try keyDown(NSClearLineFunctionKey, modifierFlags: .numericPad))
        #expect(view.isNumLockOn)
    }

    @Test(arguments: [true, false])
    func underlinesTheMarkedTextOnlyWhenTheInputMethodDoesNot(sets: Bool) throws {
        let view = TerminalContentView(session: idleSession())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let plain = NSAttributedString(string: "´")
        view.setMarkedText(plain, selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        let defaulted = try image(of: view)
        let style = sets ? NSUnderlineStyle.single : []
        let explicit = NSAttributedString(string: "´", attributes: [.underlineStyle: style.rawValue])
        view.setMarkedText(explicit, selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        #expect((try image(of: view) == defaulted) == sets)
    }

    @Test func coversTheWholeCursorCellWithTheMarkedText() async throws {
        let covered = try await markedView(running: "printf '\\033[7m \\033[m\\033[1D'")
        let empty = try await markedView(running: "exit")
        let cell = covered.cursorRect
        #expect(try bottomRows(of: cell, in: covered) == bottomRows(of: cell, in: empty))
    }

    private func markedView(running script: String) async throws -> TerminalContentView {
        let session = TerminalSession(running: script)
        let view = TerminalContentView(session: session)
        view.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        await session.waitForExit()
        view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange)
        return view
    }
}

@MainActor
private func image(of view: NSView) throws -> Data {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return try #require(representation.tiffRepresentation)
}

@MainActor
private func bottomRows(of rect: CGRect, in view: NSView) throws -> [NSColor?] {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    let scale = CGFloat(representation.pixelsWide) / representation.size.width
    let bottom = Int(rect.maxY * scale)
    return (bottom - 3 ..< bottom)
        .flatMap { y in
            (Int(rect.minX * scale) ..< Int(rect.maxX * scale)).map { representation.colorAt(x: $0, y: y) }
        }
}

@MainActor
private func idleSession() -> TerminalSession {
    TerminalSession(running: "read line")
}

private final class UnmarkingPassingInputContext: NSTextInputContext {
    override func handleEvent(_ event: NSEvent) -> Bool {
        if client.hasMarkedText() {
            client.setMarkedText(
                "",
                selectedRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            client.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        return super.handleEvent(event)
    }
}

private final class RepeatingCommandContext: NSTextInputContext {
    override func handleEvent(_ event: NSEvent) -> Bool {
        guard client.hasMarkedText() else {
            return super.handleEvent(event)
        }
        client.doCommand(by: #selector(NSResponder.moveUp(_:)))
        client.doCommand(by: #selector(NSResponder.moveToBeginningOfParagraph(_:)))
        return true
    }
}
