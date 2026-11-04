import AppKit
import TerminalCore
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalBidiTests {
    typealias Selection = TerminalContentView.Selection

    @Test(arguments: [
        ("אב", [1, 0, 2, 3, 4, 5, 6, 7]), ("א 12 ב", [5, 4, 2, 3, 1, 0, 6, 7]), ("ab אב cd", [0, 1, 2, 4, 3, 5, 6, 7]),
        ("│אב│", [0, 2, 1, 3, 4, 5, 6, 7]), ("אב中x", [1, 0, 2, 3, 4, 5, 6, 7]),
    ])
    func ordersARowWithRightToLeftText(text: String, columns: [Int]) {
        var terminal = Terminal(columns: 8, rows: 1)
        _ = terminal.receive(Array(text.utf8))
        let order = TerminalContentView.visualOrder(of: terminal.screen[0], graphemes: terminal.graphemes)
        #expect(order?.columns == columns)
    }

    @Test(arguments: ["abc 123", "│中│ é😀", ""])
    func skipsARowWithoutRightToLeftText(text: String) {
        var terminal = Terminal(columns: 8, rows: 1)
        _ = terminal.receive(Array(text.utf8))
        #expect(TerminalContentView.visualOrder(of: terminal.screen[0], graphemes: terminal.graphemes) == nil)
    }

    @Test func selectsTheLogicalTextUnderADragOverRightToLeftText() async throws {
        let view = try await view(running: "printf '\\327\\220\\327\\221 cd'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1.8, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 0.8, in: view))
        #expect(view.selectedText == "א")
    }

    @Test func selectsTheRightToLeftWordUnderADoubleClick() async throws {
        let view = try await view(running: "printf '\\327\\220\\327\\221 \\327\\222\\327\\223'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0.5, in: view, clickCount: 2))
        #expect(view.selectedText == "גד")
    }

    @Test func keepsTheLogicalOrderInTheCopyAndTheAccessibilityText() async throws {
        let view = try await view(running: "printf '\\327\\220\\327\\221 cd\\n'")
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 5))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.copySelection(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "אב cd")
        #expect((view.accessibilityValue() as? String)?.hasPrefix("אב cd\n") == true)
    }

    @Test func putsTheCursorAndTheFoundTextInTheirVisualCells() async throws {
        let view = try await view(running: "printf '\\327\\220\\327\\221\\r'")
        #expect(view.cursorRect == view.rect(row: 0, columns: 1 ..< 2))
        #expect(view.characterRects(for: NSRange(location: 1, length: 1)) == [view.rect(row: 0, columns: 0 ..< 1)])
    }
}

@MainActor
private func view(running script: String) async throws -> TerminalContentView {
    let session = TerminalSession(running: script)
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 400, height: 300))
    try session.start()
    await session.waitForExit()
    return view
}
