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
            running: "stty raw -echo; echo ready; dd bs=5 count=1 2>/dev/null | od -An -tx1"
        )
        await waitForText("ready", in: session)
        let pasteboard = pasteboard(containing: "a\nb\r\nc")
        defer { pasteboard.releaseGlobally() }
        #expect(view.readSelection(from: pasteboard))
        #expect(await lines(afterExitOf: session).contains("61  0d  62  0d  63"))
    }

    @Test func pastesNothingWithoutText() throws {
        let (view, _) = try startedView(running: "exit")
        let pasteboard = pasteboard(containing: nil)
        defer { pasteboard.releaseGlobally() }
        #expect(!view.readSelection(from: pasteboard))
    }
}

@MainActor
func startedView(running script: String) throws -> (TerminalContentView, TerminalSession) {
    let session = TerminalSession(
        configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script])
    )
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 400, height: 300))
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
