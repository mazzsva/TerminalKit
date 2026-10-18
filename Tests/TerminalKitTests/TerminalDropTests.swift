import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalDropTests {
    private let names = [
        "plain-name_1.txt", "a b", "it's", "quote\"x", "$HOME", "back\\slash", "star*?", "semi;colon&", "!bang",
        "#hash", "~tilde", "(paren)[x]{y}", "a=b", "pipe|<>", "`tick`", "é中文🙂", "tab\tx", "new\nline",
    ]

    @Test(arguments: [
        ("/a/plain-name_1.txt", "/a/plain-name_1.txt"), ("/a b", "/a\\ b"), ("/it's", "/it\\'s"),
        ("/$HOME", "/\\$HOME"), ("/é中文🙂", "/é中文🙂"), ("/a\nb", "$'/a\\x0ab'"), ("/a'b\tc", "$'/a\\'b\\x09c'"),
    ])
    func escapesAPath(path: String, escaped: String) {
        #expect(TerminalContentView.escapedPath(path) == escaped)
    }

    @Test func readsTheDroppedFiles() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(filePath: "/a b") as NSURL, URL(filePath: "/c") as NSURL])
        #expect(TerminalContentView.droppedText(from: pasteboard) == "/a\\ b /c ")
    }

    @Test func readsTheDroppedText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(TerminalContentView.droppedText(from: pasteboard) == nil)
        pasteboard.setString("echo hi", forType: .string)
        #expect(TerminalContentView.droppedText(from: pasteboard) == "echo hi")
    }

    @Test func acceptsADrop() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=6 2>/dev/null | od -An -c")
        let view = TerminalContentView(session: session)
        #expect(view.registeredDraggedTypes.contains(.fileURL))
        try session.start()
        await session.waitForText("ready")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let drag = Drag(pasteboard: pasteboard)
        #expect(view.draggingEntered(drag) == [])
        #expect(!view.performDragOperation(drag))
        pasteboard.writeObjects([URL(filePath: "/a b") as NSURL])
        #expect(view.draggingEntered(drag) == .copy)
        #expect(view.performDragOperation(drag))
        #expect(await session.linesAfterExit().contains("/   a   \\       b"))
    }

    @Test(arguments: [("/bin/zsh", ["-f"]), ("/bin/bash", ["--norc", "--noprofile"])])
    func givesTheShellTheExactPaths(shell: String, arguments: [String]) async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects(names.map { URL(filePath: "/x/" + $0) as NSURL })
        let text = try #require(TerminalContentView.droppedText(from: pasteboard))
        let session = TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: shell),
                arguments: arguments,
                environment: [
                    "HOME": "/nonexistent", "HISTFILE": "/dev/null", "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
                ]
            )
        )
        let view = TerminalContentView(session: session)
        try session.start()
        view.paste(text: "printf '<%s>\\n' " + text)
        session.send(Array("\rexit\r".utf8))
        await session.waitForExit()
        let terminal = session.terminal
        let output = (terminal.scrollback + terminal.screen)
            .map {
                String($0.filter { $0.width > 0 }.map(terminal.character(of:))).trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
        for name in names {
            #expect(output.contains("</x/" + name.replacing("\t", with: " ") + ">"), "\(name)")
        }
    }
}

@MainActor
private final class Drag: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight = NSSpringLoadingHighlight.none

    init(pasteboard: NSPasteboard) {
        draggingPasteboard = pasteboard
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
