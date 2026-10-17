import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalContentViewTests {
    @Test func fitsTheScreenToTheView() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 8 + view.cellSize.width * 100.5, height: 8 + view.cellSize.height * 30.5))
        #expect(session.terminal.columns == 100)
        #expect(session.terminal.rows == 30)
    }

    @Test func keepsAtLeastOneCell() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        TerminalContentView(session: session).fit(to: .zero)
        #expect(session.terminal.columns == 1)
        #expect(session.terminal.rows == 1)
    }

    @Test func drawsTheScreen() async throws {
        let session = TerminalSession(
            configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "printf 'hello\\r'"])
        )
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let blankImage = try image(of: view)

        try session.start()
        for await state in Observations({ session.state }) where state != .running {
            break
        }
        #expect(try image(of: view) != blankImage)
    }

    @Test func drawsTheCursor() throws {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let corner = CGPoint(x: 190, y: 90)
        #expect(color(in: representation, at: center) != color(in: representation, at: corner))
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
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "printf '\\033[41m  \\033[m'; seq 1 30"]
            )
        )
        let view = TerminalContentView(session: session)
        view.fit(to: CGSize(width: 200, height: 100))
        try session.start()
        for await state in Observations({ session.state }) where state != .running {
            break
        }
        view.fit(to: CGSize(width: 200, height: 100))
        #expect(!session.terminal.scrollback.isEmpty)
        let center = CGPoint(x: 4 + view.cellSize.width / 2, y: 4 + view.cellSize.height / 2)
        let color = try #require(color(in: try representation(of: view), at: center)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 194 / 255) < 0.02)
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
        #expect(await lines(afterExitOf: session).contains("got hi"))
    }

    @Test func sendsTheCursorKeysInTheModeOfTheProcess() async throws {
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "printf '\\033[?1h'; stty raw -echo; dd bs=3 count=1 2>/dev/null | od -An -tx1"]
            )
        )
        let view = TerminalContentView(session: session)
        try session.start()
        for await isEnabled in Observations({ session.terminal.usesApplicationCursorKeys }) where isEnabled {
            break
        }
        view.keyDown(with: try keyDown(NSUpArrowFunctionKey))
        #expect(await lines(afterExitOf: session).contains("1b  4f  41"))
    }

    @Test func sendsTextFromTheInputSystem() async throws {
        let session = readingSession()
        let view = TerminalContentView(session: session)
        try session.start()
        view.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.keyDown(with: try keyDown("\r"))
        #expect(await lines(afterExitOf: session).contains("got é"))
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
        #expect(await lines(afterExitOf: session).contains("got"))
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

    @Test func acceptsFirstResponder() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        #expect(TerminalContentView(session: session).acceptsFirstResponder)
    }
}

@MainActor
private func readingSession() -> TerminalSession {
    TerminalSession(
        configuration: .init(
            executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "read line; echo \"got $line\""])
    )
}

@MainActor
private func lines(afterExitOf session: TerminalSession) async -> [String] {
    for await state in Observations({ session.state }) where state != .running {
        break
    }
    return session.terminal.screen.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
}

@MainActor
private func drawnView(running script: String) async throws -> TerminalContentView {
    let session = TerminalSession(
        configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script])
    )
    let view = TerminalContentView(session: session)
    view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    try session.start()
    for await state in Observations({ session.state }) where state != .running {
        break
    }
    return view
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
