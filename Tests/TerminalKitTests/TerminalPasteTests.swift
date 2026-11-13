import AppKit
import CryptoKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
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
        let bytes = try await pastedBytes("a\u{1B}\u{1}b\u{1B}[200~c", mode: "\\033[?2004h", count: 16)
        #expect(bytes == "1b  5b  32  30  30  7e  61  1b  01  62  1b  5b  32  30  30  7e")
    }

    @Test(arguments: ["a\u{1B}[201~b", "a\u{1B}[201~\u{301}b", "a\u{1B}[201~\u{200D}b", "a\u{1B}[201~\u{FE0F}b"])
    func refusesTheEndMarkerInBracketedPasteMode(text: String) async throws {
        let (view, session) = try startedView(
            running: "printf '\\033[?2004h'; stty raw -echo; echo ready; head -c 1 | od -An -tx1")
        var alerts: [String] = []
        view.presentsAlert = { alert, _ in
            alerts.append(alert.messageText)
            return .alertFirstButtonReturn
        }
        await session.waitForText("ready")
        let pasteboard = pasteboard(containing: text)
        defer { pasteboard.releaseGlobally() }
        view.paste(from: pasteboard)
        session.paste(text)
        session.send("x")
        #expect(await session.linesAfterExit().contains("78"))
        #expect(alerts.count == 1 && alerts[0].hasPrefix("You cannot send the text"))
    }

    @Test func sendsTheEndMarkerOnlyAtTheEndOfABracketedPaste() {
        let pieces = ["\u{1B}", "[", "201~", "20", "1~", "\u{301}", "\u{200D}", "\u{FE0F}", "\u{9B}", "\r", "\n", "a"]
        let start = Array("\u{1B}[200~".utf8)
        let end = Array("\u{1B}[201~".utf8)
        var texts = [""]
        for _ in 1 ... 5 {
            texts = texts.flatMap { text in pieces.map { text + $0 } }
            for text in texts {
                let lines = Array(text.replacing("\r\n", with: "\r").replacing("\n", with: "\r").utf8)
                guard let bytes = TerminalSession.pastedBytes(text, isBracketed: true) else {
                    #expect(lines.firstRange(of: end) != nil, "\(Array(text.unicodeScalars))")
                    continue
                }
                #expect(bytes == start + lines + end, "\(Array(text.unicodeScalars))")
                #expect(bytes.firstRange(of: end)?.lowerBound == bytes.count - end.count)
            }
        }
    }

    @Test func keepsAPastedCommandFromRunningInZsh() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/zsh"),
                arguments: ["-f"],
                environment: [
                    "HOME": "/nonexistent", "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
                ]
            )
        )
        let view = TerminalContentView(session: session)
        view.presentsAlert = { _, _ in .alertFirstButtonReturn }
        view.fit(to: CGSize(width: 800, height: 300))
        try session.start()
        for await isBracketed in Observations({ session.terminal.usesBracketedPaste }) where isBracketed {
            break
        }
        let path = folder.path(percentEncoded: false)
        view.paste(text: "echo a\u{1B}[201~\u{301}\ntouch '\(path)/ended'\n")
        view.paste(text: "touch '\(path)/pasted'\n")
        session.send("\u{7}echo do''ne; exit\r")
        #expect(await session.linesAfterExit().contains { $0.hasPrefix("done") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: path).isEmpty)
    }

    @Test(arguments: [
        (
            NSApplication.ModalResponse.alertFirstButtonReturn,
            "61  01  62  1b  63  7f  64  c2  9b  65  09  0d  0b  0c  c2  85"
        ),
        (.alertSecondButtonReturn, "61  62  63  64  65  09  0d  0b  0c  c2  85  78"), (.cancel, "78"),
    ])
    func asksBeforeItPastesControlCharacters(response: NSApplication.ModalResponse, bytes: String) async throws {
        let count = bytes.split(separator: " ").count
        let (view, session) = try startedView(running: "stty raw -echo; echo ready; head -c \(count) | od -An -tx1")
        var buttons: [[String]] = []
        view.presentsAlert = { alert, _ in
            buttons.append(alert.buttons.map(\.title))
            return response
        }
        await session.waitForText("ready")
        let pasteboard = pasteboard(containing: "a\u{1}b\u{1B}c\u{7F}d\u{9B}e\t\n\u{B}\u{C}\u{85}")
        defer { pasteboard.releaseGlobally() }
        view.paste(from: pasteboard)
        session.send("x")
        #expect(await session.linesAfterExit().contains(bytes))
        #expect(buttons == [["Paste", "Paste without Control Characters", "Cancel"]])
    }

    @Test func pastesWhitespaceControlsWithoutAsking() async throws {
        let (view, session) = try startedView(running: "stty raw -echo; echo ready; head -c 7 | od -An -tx1")
        view.presentsAlert = { _, _ in .cancel }
        await session.waitForText("ready")
        let pasteboard = pasteboard(containing: "\t\n\u{B}\u{C}\r\u{85}")
        defer { pasteboard.releaseGlobally() }
        view.paste(from: pasteboard)
        #expect(await session.linesAfterExit().contains("09  0d  0b  0c  0d  c2  85"))
    }

    @Test func pastesWithoutBracketsAfterTheModeEnds() async throws {
        let bytes = try await pastedBytes("ab", mode: "\\033[?2004h\\033[?2004l", count: 2)
        #expect(bytes == "61  62")
    }

    @Test func pastesALargeTextWhole() async throws {
        let text = String(repeating: "abcdefgh", count: 1 << 17)
        let input = "\u{1B}[200~\(text)\u{1B}[201~"
        let session = TerminalSession(
            running: """
                printf '\\033[?2004h'; stty raw -echo; echo ready; head -c \(input.utf8.count) | shasum -a 256
                """
        )
        try session.start()
        await session.waitForText("ready")
        session.paste(text)
        let hash = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(await session.linesAfterExit().contains { $0.hasPrefix(hash) })
    }

    @Test func pastesNothingForAnImage() async throws {
        let (bytes, canPaste) = try await pastedImageBytes(mode: "\\033[?2004h", count: 1)
        #expect(!canPaste)
        #expect(bytes == "78")
    }

    @Test func pastesTheTextOverAnImage() async throws {
        let (bytes, canPaste) = try await pastedImageBytes(text: "a", mode: "\\033[?2004h", count: 14)
        #expect(canPaste)
        #expect(bytes == "1b  5b  32  30  30  7e  61  1b  5b  32  30  31  7e  78")
    }

    @Test func pastesTheTextWithoutAnImage() async throws {
        let (bytes, canPaste) = try await pastedImageBytes(image: false, text: "a", mode: "", count: 2)
        #expect(canPaste)
        #expect(bytes == "61  78")
    }

    @Test func pastesACopiedFileAsItsPath() async throws {
        let item = NSPasteboardItem()
        item.setString(URL(filePath: "/tmp/My Shot.png").absoluteString, forType: .fileURL)
        item.setString("My Shot.png", forType: .string)
        #expect(try await pastedLines([item]).contains("</tmp/My\\ Shot.png >"))
    }

    @Test func turnsOffPasteForAFileWithoutText() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(filePath: "/tmp/My Shot.png") as NSURL])
        #expect(!view.canPaste(from: pasteboard))
    }
}

@MainActor
private func pastedLines(_ objects: [any NSPasteboardWriting]) async throws -> [String] {
    let (view, session) = try startedView(running: "IFS= read -r a; printf '<%s>\\n' \"$a\"")
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.writeObjects(objects)
    view.paste(from: pasteboard)
    session.send("\r")
    return await session.linesAfterExit()
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
private func pastedImageBytes(
    image: Bool = true, text: String? = nil, mode: String, count: Int
) async throws -> (bytes: String?, canPaste: Bool) {
    let (view, session) = try startedView(
        running: "printf '\(mode)'; stty raw -echo; echo ready; head -c \(count) | od -An -tx1"
    )
    await session.waitForText("ready")
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    if image {
        pasteboard.setData(Data([0]), forType: .tiff)
    }
    if let text {
        pasteboard.setString(text, forType: .string)
    }
    let canPaste = view.canPaste(from: pasteboard)
    view.paste(from: pasteboard)
    session.send("x")
    return (await session.linesAfterExit().first { !$0.isEmpty && $0 != "ready" }, canPaste)
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
