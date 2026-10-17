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
        view.setFrameSize(
            NSSize(width: 8 + view.cellSize.width * 100.5, height: 8 + view.cellSize.height * 30.5)
        )
        #expect(session.terminal.columns == 100)
        #expect(session.terminal.rows == 30)
    }

    @Test func keepsAtLeastOneCell() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        TerminalContentView(session: session).setFrameSize(.zero)
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

    @Test func sendsKeyPressesToTheSession() async throws {
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "read line; echo \"got $line\""])
        )
        let view = TerminalContentView(session: session)
        try session.start()
        for characters in ["h", "i", "\r"] {
            view.keyDown(with: try keyDown(characters))
        }
        for await state in Observations({ session.state }) where state != .running {
            break
        }
        let lines = session.terminal.screen.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("got hi"))
    }

    @Test func acceptsFirstResponder() {
        let session = TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh")))
        #expect(TerminalContentView(session: session).acceptsFirstResponder)
    }
}

@MainActor
private func image(of view: NSView) throws -> Data {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return try #require(representation.tiffRepresentation)
}

@MainActor
private func color(in representation: NSBitmapImageRep, at point: CGPoint) -> NSColor? {
    let scale = CGFloat(representation.pixelsWide) / representation.size.width
    return representation.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))
}
