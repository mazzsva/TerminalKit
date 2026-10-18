import AppKit
import Foundation
import SwiftUI
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalContentViewTests {
    @Test func fitsTheScreenToTheView() {
        let session = TerminalSession(running: "exit")
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 8 + view.cellSize.width * 100.5, height: 8 + view.cellSize.height * 30.5))
        #expect(session.terminal.columns == 100)
        #expect(session.terminal.rows == 30)
    }

    @Test func keepsAtLeastOneCell() {
        let session = TerminalSession(running: "exit")
        TerminalContentView(session: session).fit(to: .zero)
        #expect(session.terminal.columns == 1)
        #expect(session.terminal.rows == 1)
    }

    @Test func makesTheStyledFontsFromTheFont() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        view.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        #expect(view.fonts.bold.pointSize == 20)
        #expect(view.fonts.bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(view.fonts.boldItalic.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
    }

    @Test func drawsTheScreen() async throws {
        let session = TerminalSession(running: "printf 'hello\\r'")
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let blankImage = try image(of: view)

        try session.start()
        await session.waitForExit()
        #expect(try image(of: view) != blankImage)
    }

    @Test func drawsTheCursor() throws {
        let session = TerminalSession(running: "exit")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let corner = CGPoint(x: 190, y: 90)
        #expect(color(in: representation, at: center) != color(in: representation, at: corner))
        #expect(window.firstResponder === view)
    }

    @Test func drawsAnUnderlineCursor() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[4 q'")
        let rect = view.cursorRect
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.maxY - 1)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.maxY - 3)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.midY)), to: background))
        #expect(window.firstResponder === view)
    }

    @Test func drawsABarCursor() async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[6 q'")
        let rect = view.cursorRect
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.minX + 1, y: rect.midY)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.minX + 3, y: rect.midY)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.midY)), to: background))
        #expect(window.firstResponder === view)
    }

    @Test(arguments: [("4", CGRect(x: 0, y: 0, width: 0, height: 3)), ("6", CGRect(x: 3, y: 0, width: 0, height: 0))])
    func drawsTheTextUnderAThinCursor(shape: String, inset: CGRect) async throws {
        let (thin, thinWindow) = try await focusedView(running: "printf 'X\\b\\033[\(shape) q'")
        let (hidden, hiddenWindow) = try await focusedView(running: "printf 'X\\b\\033[?25l'")
        let rect = CGRect(
            x: thin.cursorRect.minX + inset.minX,
            y: thin.cursorRect.minY,
            width: thin.cursorRect.width - inset.minX,
            height: thin.cursorRect.height - inset.height
        )
        #expect(try pixels(in: rect, of: thin) == pixels(in: rect, of: hidden))
        #expect(try Set(pixels(in: rect, of: thin).map { $0?.description }).count > 1)
        #expect(thinWindow.firstResponder === thin && hiddenWindow.firstResponder === hidden)
    }

    @Test(arguments: ["4", "6"])
    func drawsAHollowCursorOfEachShapeWithoutTheFocus(shape: String) async throws {
        let (view, window) = try await focusedView(running: "printf '\\033[\(shape) q'")
        window.isKey = false
        let rect = view.cursorRect
        let representation = try representation(of: view)
        let background = color(in: representation, at: CGPoint(x: 190, y: 90))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.maxX - 0.5, y: rect.midY)), to: background))
        #expect(!isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.minY + 0.5)), to: background))
        #expect(isClose(color(in: representation, at: CGPoint(x: rect.midX, y: rect.midY)), to: background))
    }

    @Test func drawsAHollowCursorWithoutTheFocus() async throws {
        let (view, window) = try await focusedView(running: "exit")
        let edge = CGPoint(x: view.cursorRect.minX + 0.5, y: view.cursorRect.midY)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let corner = CGPoint(x: 190, y: 90)
        let focused = try representation(of: view)
        let cursor = color(in: focused, at: center)
        #expect(!isClose(cursor, to: color(in: focused, at: corner)))

        window.isKey = false
        let unfocused = try representation(of: view)
        #expect(isClose(color(in: unfocused, at: edge), to: cursor))
        #expect(isClose(color(in: unfocused, at: center), to: color(in: unfocused, at: corner)))

        window.isKey = true
        #expect(isClose(color(in: try representation(of: view), at: center), to: cursor))
    }

    @Test func drawsAHollowCursorWhenAnotherViewHasTheFocus() async throws {
        let (view, window) = try await focusedView(running: "exit")
        let textView = NSTextView()
        view.addSubview(textView)
        window.makeFirstResponder(textView)
        let representation = try representation(of: view)
        let center = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        let corner = CGPoint(x: 190, y: 90)
        #expect(isClose(color(in: representation, at: center), to: color(in: representation, at: corner)))
        #expect(!view.isFocused)

        window.makeFirstResponder(view)
        #expect(view.isFocused)
    }

    @Test func losesTheFocusWhenItLeavesTheWindow() async throws {
        let (view, window) = try await focusedView(running: "exit")
        let container = NSView()
        window.contentView = container
        #expect(!view.isFocused)

        container.addSubview(view)
        #expect(view.isFocused)
    }

    @Test func reportsTheFocusWhenTheProcessAsks() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[?1004h'; dd bs=1 count=6 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        window.isKey = false
        try session.start()
        for await isEnabled in Observations({ session.terminal.usesFocusReporting }) where isEnabled {
            break
        }
        window.isKey = true
        window.isKey = true
        window.isKey = false
        #expect(await session.linesAfterExit().contains("1b  5b  49  1b  5b  4f"))
    }

    @Test func reportsNoFocusWhenTheProcessDoesNotAsk() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        try session.start()
        await session.waitForText("ready")
        window.isKey = false
        window.isKey = true
        view.keyDown(with: try keyDown("a"))
        #expect(await session.linesAfterExit().contains("61"))
    }

    @Test func drawsTheCharacterUnderTheCursor() async throws {
        var palette = TerminalPalette.standard
        palette.cursor = .red
        let (character, characterWindow) = try await focusedView(running: "printf 'X\\b'")
        let (space, spaceWindow) = try await focusedView(running: "printf ' \\b'")
        character.palette = palette
        space.palette = palette
        #expect(try pixels(in: character.cursorRect, of: character) != pixels(in: space.cursorRect, of: space))
        #expect(characterWindow.firstResponder === character && spaceWindow.firstResponder === space)
    }

    @Test func coversAWideCharacterWithTheCursor() async throws {
        let view = try await drawnView(running: "printf '中\\b\\b'")
        #expect(view.cursorRect.width == 2 * view.cellSize.width)
    }

    @Test func hidesTheCursor() async throws {
        let view = try await drawnView(running: "printf '\\033[?25l'")
        let representation = try representation(of: view)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        #expect(color(in: representation, at: center) == color(in: representation, at: CGPoint(x: 190, y: 90)))
    }

    @Test func drawsTheTextAfterAWideCharacterInItsCell() async throws {
        let wide = try await drawnView(running: "printf '中x\\n'")
        let narrow = try await drawnView(running: "printf '  x\\n'")
        let cell = CGRect(
            x: 4 + 2 * wide.cellSize.width,
            y: 4,
            width: wide.cellSize.width,
            height: wide.cellSize.height
        )
        #expect(try pixels(in: cell, of: wide) == pixels(in: cell, of: narrow))
    }

    @Test func drawsTheBackgroundColor() async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[m'")
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 194 / 255) < 0.02)
        #expect(abs(color.greenComponent - 54 / 255) < 0.02)
        #expect(abs(color.blueComponent - 33 / 255) < 0.02)
    }

    @Test func drawsTheScrollback() async throws {
        let session = TerminalSession(running: "printf '\\033[41m  \\033[m'; seq 1 30")
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 200, height: 100))
        try session.start()
        await session.waitForExit()
        view.fit(to: CGSize(width: 200, height: 100))
        #expect(!session.terminal.scrollback.isEmpty)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 194 / 255) < 0.02)
    }

    @Test func drawsWithThePalette() async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[m'")
        var palette = TerminalPalette.standard
        palette.background = Color(.sRGB, red: 0.2, green: 0.3, blue: 0.4)
        palette.ansiColors[1] = Color(.sRGB, red: 0.4, green: 0.6, blue: 0.2)
        view.palette = palette
        let representation = try representation(of: view)
        let cell = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        #expect(isClose(color(in: representation, at: cell), to: [0.4, 0.6, 0.2]))
        #expect(isClose(color(in: representation, at: CGPoint(x: 190, y: 90)), to: [0.2, 0.3, 0.4]))
    }

    @Test func makesAPaletteWithFewerANSIColors() {
        let palette = TerminalPalette(
            foreground: .white, background: .black, cursor: .gray, selection: .blue, ansiColors: [.red])
        #expect(palette.ansiColors == [.red])
    }

    @Test(arguments: [2, 20])
    func fillsTheANSIColorsFromTheStandardPalette(count: Int) async throws {
        let view = try await drawnView(running: "printf '\\033[41m  \\033[47m  \\033[107m  \\033[m'")
        var palette = TerminalPalette.standard
        palette.ansiColors =
            [.black, Color(.sRGB, red: 0.4, green: 0.6, blue: 0.2)]
            + Array(repeating: Color(.sRGB, red: 0.1, green: 0.9, blue: 0.5), count: count - 2)
        view.palette = palette
        let representation = try representation(of: view)
        let points = [0, 2, 4]
            .map { CGPoint(x: 4 + view.cellSize.width * (CGFloat($0) + 0.5), y: 4 + view.cellSize.height / 2) }
        let fill: [CGFloat] = count > 2 ? [0.1, 0.9, 0.5] : [203.0 / 255, 204.0 / 255, 205.0 / 255]
        let brightFill: [CGFloat] = count > 2 ? [0.1, 0.9, 0.5] : [233.0 / 255, 235.0 / 255, 235.0 / 255]
        #expect(isClose(color(in: representation, at: points[0]), to: [0.4, 0.6, 0.2]))
        #expect(isClose(color(in: representation, at: points[1]), to: fill))
        #expect(isClose(color(in: representation, at: points[2]), to: brightFill))
    }

    @Test func drawsTheForegroundColor() async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let red = try image(of: try await drawnView(running: "printf '\\033[31mX\\r'"))
        #expect(red != plain)
    }

    @Test(arguments: ["1", "2", "3", "4", "9"])
    func drawsTheTextStyle(parameter: String) async throws {
        let plain = try image(of: try await drawnView(running: "printf 'X\\r'"))
        let styled = try image(of: try await drawnView(running: "printf '\\033[\(parameter)mX\\r'"))
        #expect(styled != plain)
    }

    @Test func drawsInverseText() async throws {
        let view = try await drawnView(running: "printf '\\033[7m  \\033[m'")
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let representation = try representation(of: view)
        #expect(color(in: representation, at: center) != color(in: representation, at: CGPoint(x: 190, y: 90)))
    }

    @Test func hidesHiddenText() async throws {
        let blank = try image(of: try await drawnView(running: "printf ' \\r'"))
        let hidden = try image(of: try await drawnView(running: "printf '\\033[8mX\\r'"))
        #expect(hidden == blank)
    }

    @Test func sendsKeyPressesToTheSession() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        for characters in ["h", "i", "\r"] {
            view.keyDown(with: try keyDown(characters))
        }
        #expect(await session.linesAfterExit().contains("got hi"))
    }

    @Test func sendsTheCursorKeysInTheModeOfTheProcess() async throws {
        let session = TerminalSession(
            running: "printf '\\033[?1h'; stty raw -echo; dd bs=3 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        for await isEnabled in Observations({ session.terminal.usesApplicationCursorKeys }) where isEnabled {
            break
        }
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey))
        #expect(await session.linesAfterExit().contains("1b  4f  41"))
    }

    @Test(arguments: [(true, "1b  61"), (false, "c3  a5")])
    func sendsTheOptionKeyAsMetaWhenItIsOn(isOn: Bool, bytes: String) async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 2 | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.usesOptionAsMetaKey = isOn
        try session.start()
        await session.waitForText("ready")
        view.keyDown(with: try keyDown("å", charactersIgnoringModifiers: "a", modifierFlags: .option))
        #expect(await session.linesAfterExit().contains(bytes))
    }

    @Test func sendsControlKeysThatTheInputSystemDrops() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        for key in ["/", "2", "6", "?"] {
            view.keyDown(with: try keyDown(key, modifierFlags: .control))
        }
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1f  00  1e  7f  78"))
    }

    @Test func leavesControlKeysToTheMarkedText() async throws {
        let session = TerminalSession(
            running: """
                stty raw -echo; echo ready
                while byte=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' '); [ "$byte" != 78 ]; do
                    echo "got $byte"
                done
                """
        )
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.keyDown(with: try keyDown("2", modifierFlags: .control))
        view.unmarkText()
        view.keyDown(with: try keyDown("x"))
        #expect(await !session.linesAfterExit().contains { $0.contains("got 00") })
    }

    @Test func sendsAKeyWithTwoCommandsOnce() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; head -c 7 | od -An -tx1")
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("ready")
        let up = String(try #require(UnicodeScalar(NSUpArrowFunctionKey)))
        let optionUp = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.option, .function, .numericPad],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: up,
                charactersIgnoringModifiers: up,
                isARepeat: false,
                keyCode: 126
            )
        )
        view.keyDown(with: optionUp)
        view.keyDown(with: try keyDown("x"))
        #expect(await session.linesAfterExit().contains("1b  5b  31  3b  33  41  78"))
    }

    @Test func sendsTextFromTheInputSystem() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        view.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.keyDown(with: try keyDown("\r"))
        #expect(await session.linesAfterExit().contains("got é"))
    }

    @Test func keepsTheMarkedTextUntilTheInsert() {
        let view = TerminalContentView(session: readingSession())
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 0, length: 1))
        view.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
    }

    @Test func dropsTheMarkedTextWhenUnmarked() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        view.unmarkText()
        view.keyDown(with: try keyDown("\r"))
        #expect(!view.hasMarkedText())
        #expect(await session.linesAfterExit().contains("got"))
    }

    @Test func drawsTheMarkedText() throws {
        let view = TerminalContentView(session: readingSession())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let cursorImage = try image(of: view)
        view.setMarkedText(
            "´",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(try image(of: view) != cursorImage)
        view.unmarkText()
        #expect(try image(of: view) == cursorImage)
    }

    @Test func placesTheInputWindowAtTheCursor() {
        let view = TerminalContentView(session: readingSession())
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 300, height: 150),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        let rect = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        #expect(rect.origin == CGPoint(x: 104, y: 346 - view.cellSize.height))
        #expect(rect.size == view.cellSize)
    }
}

@MainActor
private func readingSession() -> TerminalSession {
    TerminalSession(running: "read line; echo \"got $line\"")
}

@MainActor
private func drawnView(running script: String) async throws -> TerminalContentView {
    let session = TerminalSession(running: script)
    let view = TerminalContentView(session: session)
    view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    try session.start()
    await session.waitForExit()
    return view
}

@MainActor
private func focusedView(running script: String) async throws -> (view: TerminalContentView, window: KeyWindow) {
    let session = TerminalSession(running: script)
    let view = TerminalContentView(session: session)
    let window = KeyWindow(contentView: view)
    view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    try session.start()
    await session.waitForExit()
    return (view, window)
}

@MainActor
private func image(of view: NSView) throws -> Data {
    try #require(try representation(of: view).tiffRepresentation)
}

@MainActor
private func representation(of view: NSView) throws -> NSBitmapImageRep {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return representation
}

@MainActor
private func color(in representation: NSBitmapImageRep, at point: CGPoint) -> NSColor? {
    let scale = CGFloat(representation.pixelsWide) / representation.size.width
    return representation.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))
}

@MainActor
private func pixels(in rect: CGRect, of view: NSView) throws -> [NSColor?] {
    let representation = try representation(of: view)
    let scale = CGFloat(representation.pixelsWide) / representation.size.width
    return stride(from: Int(rect.minY * scale), to: Int(rect.maxY * scale), by: 1)
        .flatMap { y in
            stride(from: Int(rect.minX * scale), to: Int(rect.maxX * scale), by: 1)
                .map { x in representation.colorAt(x: x, y: y) }
        }
}

private func isClose(_ color: NSColor?, to other: NSColor?) -> Bool {
    guard let other = other?.usingColorSpace(.sRGB) else {
        return false
    }
    return isClose(color, to: [other.redComponent, other.greenComponent, other.blueComponent])
}

private func isClose(_ color: NSColor?, to components: [CGFloat]) -> Bool {
    guard let color = color?.usingColorSpace(.sRGB) else {
        return false
    }
    return zip([color.redComponent, color.greenComponent, color.blueComponent], components)
        .allSatisfy { abs($0 - $1) < 0.02 }
}
