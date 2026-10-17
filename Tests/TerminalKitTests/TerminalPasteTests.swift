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
        #expect(view.readSelection(from: pasteboard))
        #expect(await lines(afterExitOf: session).contains("hello+world"))
    }

    @Test func sendsAReturnForEachLineBreak() async throws {
        let (view, session) = try startedView(
            running: "stty raw -echo; echo ready; head -c 5 | od -An -tx1"
        )
        await waitForText("ready", in: session)
        let pasteboard = pasteboard(containing: "a\nb\r\nc")
        defer { pasteboard.releaseGlobally() }
        #expect(view.readSelection(from: pasteboard))
        #expect(await lines(afterExitOf: session).contains("61  0d  62  0d  63"))
    }

    @Test func bracketsThePasteInBracketedPasteMode() async throws {
        let bytes = try await pastedBytes("a\u{1B}[201~b", mode: "\\033[?2004h", count: 15)
        #expect(bytes == "1b  5b  32  30  30  7e  61  5b  32  30  31  7e  62  1b  5b")
    }

    @Test func pastesWithoutBracketsAfterTheModeEnds() async throws {
        let bytes = try await pastedBytes("ab", mode: "\\033[?2004h\\033[?2004l", count: 2)
        #expect(bytes == "61  62")
    }

    @Test func takesTextFromServices() throws {
        let (view, _) = try startedView(running: "exit")
        #expect(view.validRequestor(forSendType: nil, returnType: .string) as? NSView === view)
        #expect(view.validRequestor(forSendType: .string, returnType: .string) as? NSView !== view)
        view.selection = .init(anchor: .init(line: 0, column: 0), head: .init(line: 1, column: 0))
        #expect(view.validRequestor(forSendType: .string, returnType: .string) as? NSView === view)
        #expect(view.validRequestor(forSendType: nil, returnType: .fileURL) as? NSView !== view)
    }

    @Test func pastesNothingWithoutText() throws {
        let (view, _) = try startedView(running: "exit")
        let pasteboard = pasteboard(containing: nil)
        defer { pasteboard.releaseGlobally() }
        #expect(!view.readSelection(from: pasteboard))
    }
}

@MainActor
private func pastedBytes(_ text: String, mode: String, count: Int) async throws -> String? {
    let (view, session) = try startedView(
        running: "printf '\(mode)'; stty raw -echo; echo ready; head -c \(count) | od -An -tx1"
    )
    await waitForText("ready", in: session)
    let pasteboard = pasteboard(containing: text)
    defer { pasteboard.releaseGlobally() }
    #expect(view.readSelection(from: pasteboard))
    return await lines(afterExitOf: session).first { !$0.isEmpty && $0 != "ready" }
}

@MainActor
func startedView(running script: String) throws -> (TerminalContentView, TerminalSession) {
    let session = TerminalSession(
        configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script])
    )
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 800, height: 300))
    try session.start()
    return (view, session)
}

@MainActor
func pasteboard(containing text: String?) -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    pasteboard.clearContents()
    if let text {
        pasteboard.setString(text, forType: .string)
    }
    return pasteboard
}

@MainActor
private func lines(afterExitOf session: TerminalSession) async -> [String] {
    for await state in Observations({ session.state }) where state != .running {
        break
    }
    return session.terminal.screen.map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
}

@MainActor
func waitForText(_ text: String, in session: TerminalSession) async {
    for await lines in Observations({ session.terminal.screen.map { String($0.map(\.character)) } })
    where lines.contains(where: { $0.contains(text) }) {
        break
    }
}
