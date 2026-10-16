import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
struct TerminalContentViewTests {
    @Test func drawsTheScreen() async throws {
        let session = TerminalSession(
            configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", "printf hello"])
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
}

@MainActor
private func image(of view: NSView) throws -> Data {
    let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: representation)
    return try #require(representation.tiffRepresentation)
}
