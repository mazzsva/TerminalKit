import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
struct TerminalPasteTests {
    @Test func pastesTheText() async throws {
        let (view, session) = try startedView(running: "read a; read b; echo \"$a+$b\"")
        let pasteboard = pasteboard(containing: "hello\nworld\n")
        defer { pasteboard.releaseGlobally() }
        view.paste(from: pasteboard)
        #expect(await session.linesAfterExit().contains("hello+world"))
    }

    @Test func sendsAReturnForEachLineBreak() async throws {
        let (view, session) = try startedView(
            running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1"
        )
        await session.waitForText("ready")
        let pasteboard = pasteboard(containing: "a\nb\r\nc")
        defer { pasteboard.releaseGlobally() }
        view.paste(from: pasteboard)
        #expect(await session.linesAfterExit().contains("61  0d  62  0d  63"))
    }

    @Test func bracketsThePasteInBracketedPasteMode() async throws {
        let bytes = try await pastedBytes("a\u{1B}[201~b", mode: "\\033[?2004h", count: 15)
        #expect(bytes == "1b  5b  32  30  30  7e  61  5b  32  30  31  7e  62  1b  5b")
    }

    @Test func pastesWithoutBracketsAfterTheModeEnds() async throws {
        let bytes = try await pastedBytes("ab", mode: "\\033[?2004h\\033[?2004l", count: 2)
        #expect(bytes == "61  62")
    }
}

@MainActor
private func pastedBytes(_ text: String, mode: String, count: Int) async throws -> String? {
    let (view, session) = try startedView(
        running: "printf '\(mode)'; stty raw -echo; echo ready; head -c \(count) | od -An -tx1"
    )
    await session.waitForText("ready")
    let pasteboard = pasteboard(containing: text)
    defer { pasteboard.releaseGlobally() }
    view.paste(from: pasteboard)
    return await session.linesAfterExit().first { !$0.isEmpty && $0 != "ready" }
}

@MainActor
func startedView(running script: String) throws -> (TerminalContentView, TerminalSession) {
    let session = TerminalSession(running: script)
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 800, height: 300))
    try session.start()
    return (view, session)
}

@MainActor
func pasteboard(containing text: String) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    return pasteboard
}
