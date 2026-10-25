import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalSelectionTests {
    typealias Selection = TerminalContentView.Selection

    @Test func selectsColumnsInOneLine() {
        let selection = Selection(anchor: .init(line: 2, column: 1), head: .init(line: 2, column: 4))
        #expect(selection.columns(inLine: 2, count: 10) == 1 ..< 4)
        #expect(selection.columns(inLine: 1, count: 10) == nil)
        #expect(selection.columns(inLine: 3, count: 10) == nil)
    }

    @Test func selectsColumnsAcrossLines() {
        let selection = Selection(anchor: .init(line: 1, column: 6), head: .init(line: 3, column: 2))
        #expect(selection.columns(inLine: 1, count: 10) == 6 ..< 10)
        #expect(selection.columns(inLine: 2, count: 10) == 0 ..< 10)
        #expect(selection.columns(inLine: 3, count: 10) == 0 ..< 2)
    }

    @Test func selectsBackward() {
        let selection = Selection(anchor: .init(line: 3, column: 2), head: .init(line: 1, column: 6))
        #expect(selection.columns(inLine: 1, count: 10) == 6 ..< 10)
        #expect(selection.columns(inLine: 3, count: 10) == 0 ..< 2)
    }

    @Test func selectsNothingWithoutADrag() {
        let selection = Selection(anchor: .init(line: 1, column: 3), head: .init(line: 1, column: 3))
        #expect(selection.columns(inLine: 1, count: 10)?.isEmpty == true)
    }

    @Test func keepsTheColumnsInTheLine() {
        let selection = Selection(anchor: .init(line: 1, column: 3), head: .init(line: 1, column: 9))
        #expect(selection.columns(inLine: 1, count: 5) == 3 ..< 5)
    }

    @Test func selectsWithTheMouse() throws {
        let view = viewInWindow()
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 3, in: view))
        #expect(view.selection == Selection(anchor: .init(line: 0, column: 1), head: .init(line: 1, column: 3)))
    }

    @Test func startsANewSelectionWithEachClick() throws {
        let view = viewInWindow()
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 3, in: view))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 2, in: view))
        #expect(view.selection == Selection(anchor: .init(line: 2, column: 2), head: .init(line: 2, column: 2)))
    }

    @Test(arguments: [
        ("hello foo_bar world", 12.75, "foo_bar"), ("ls /usr/local/bin", 9, "local"), ("中文字符 abc", 5, "字符"),
        ("😀😀😀 e\u{301}té zz", 8, "été"), ("one two", -0.5, "one"),
    ])
    func selectsAWordWithADoubleClick(text: String, column: CGFloat, word: String) async throws {
        let view = try await view(running: "printf '\(text)'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: column, in: view, clickCount: 2))
        #expect(view.selectedText == word)
    }

    @Test func selectsBothColumnsOfAWideCharacter() async throws {
        let view = try await view(running: "printf '中文字符 abc'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 2, in: view, clickCount: 2))
        #expect(view.selection == Selection(anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 4)))
    }

    @Test(arguments: [(1.4, 5.4, 2, 6, "文字"), (0.6, 4.6, 0, 4, "中文")])
    func selectsAWideCharacterAsAWholeWithTheMouse(
        start: CGFloat, end: CGFloat, anchor: Int, head: Int, text: String
    ) async throws {
        let view = try await view(running: "printf '中文字符'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: start, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: end, in: view))
        #expect(view.selection == Selection(anchor: .init(line: 0, column: anchor), head: .init(line: 0, column: head)))
        #expect(view.selectedText == text)
    }

    @Test func keepsTheSelectionInTheLinesWhenDraggingOutside() async throws {
        let view = try await view(running: "printf 'one two'")
        let rows = view.session.terminal.rows
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 3, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: -3, column: 1, in: view))
        #expect(view.selection == Selection(anchor: .init(line: 0, column: 3), head: .init(line: 0, column: 1)))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: rows + 3, column: 1, in: view))
        #expect(view.selection == Selection(anchor: .init(line: 0, column: 3), head: .init(line: rows - 1, column: 1)))
    }

    @Test func selectsNoWordOutsideTheText() async throws {
        let view = try await view(running: "printf 'one two'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 6, in: view, clickCount: 2))
        #expect(view.selectedText == "two")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 7, in: view, clickCount: 2))
        #expect(view.selection == Selection(anchor: .init(line: 0, column: 7), head: .init(line: 0, column: 7)))
    }

    @Test func selectsAWordAcrossASoftWrap() async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); i=3; s=''; while [ $i -lt $c ]; do s=\"${s}x\"; i=$((i+1)); done; "
                + "printf '%s ab%syyycd gh' \"$s\" \"$s\""
        )
        let word = "ab" + String(repeating: "x", count: view.session.terminal.columns - 3) + "yyycd"
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 1, in: view, clickCount: 2))
        #expect(view.selectedText == word)
        let column = CGFloat(view.session.terminal.columns) + 0.2
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: column, in: view, clickCount: 2))
        #expect(view.selectedText == word)
    }

    @Test func selectsAWordInTheTrimmedScrollback() async throws {
        let view = try await view(running: "seq 1 12000")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, clickCount: 2))
        let removed = view.session.terminal.removedScrollbackCount
        let head = Selection.Point(line: removed, column: "\(removed + 1)".count)
        #expect(view.selection == Selection(anchor: .init(line: removed, column: 0), head: head))
    }

    @Test func selectsAWordWithACommandDoubleClick() async throws {
        let view = try await view(running: "printf 'hello world'")
        view.mouseDown(
            with: try mouseEvent(.leftMouseDown, row: 0, column: 7, in: view, modifierFlags: .command, clickCount: 2))
        #expect(view.selectedText == "world")
    }

    @Test func extendsByWordsWhenDraggingAfterADoubleClick() async throws {
        let view = try await view(running: "printf 'one two three four'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 9, in: view, clickCount: 2))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 15, in: view))
        #expect(view.selectedText == "three four")
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 1, in: view))
        #expect(view.selectedText == "one two three")
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: -1, column: 1, in: view))
        #expect(view.selectedText == "one two three")
    }

    @Test(arguments: [3, 4])
    func selectsALineAcrossASoftWrapWithATripleClick(clickCount: Int) async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); i=0; s=''; while [ $i -lt $c ]; do s=\"${s}x\"; i=$((i+1)); done; "
                + "printf 'before\\n'; i=0; while [ $i -lt 70 ]; do printf %s \"$s\"; i=$((i+1)); done; printf 'yz\\nafter'"
        )
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 1, in: view, clickCount: clickCount))
        #expect(view.selectedText == String(repeating: "x", count: view.session.terminal.columns * 70) + "yz")
    }

    @Test func selectsNoLineBelowTheLastLineWithATripleClick() async throws {
        let view = try await view(running: "seq 1 12000")
        let terminal = view.session.terminal
        let row = terminal.scrollback.count + terminal.rows - 2
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: row, column: 1, in: view, clickCount: 3))
        let line = terminal.removedScrollbackCount + row
        #expect(
            view.selection
                == Selection(anchor: .init(line: line, column: 0), head: .init(line: line, column: terminal.columns))
        )
        #expect(view.selectedText == "12000")
    }

    @Test func selectsALineOnlyInItsScreenWithATripleClick() async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); r=$(stty size | cut -d' ' -f1); i=0; "
                + "while [ $i -lt $((2*c+3)) ]; do printf a; i=$((i+1)); done; "
                + "i=1; while [ $i -lt $r ]; do printf '\\n'; i=$((i+1)); done; printf '\\033[?1049h\\033[Hbbb'"
        )
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, clickCount: 3))
        #expect(view.selectedText == String(repeating: "a", count: 2 * view.session.terminal.columns))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 1, in: view, clickCount: 3))
        #expect(view.selectedText == "bbb")
    }

    @Test func copiesTheScrollbackAndTheAlternateScreenAsSeparateLines() async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); r=$(stty size | cut -d' ' -f1); i=0; "
                + "while [ $i -lt $((2*c+3)) ]; do printf a; i=$((i+1)); done; "
                + "i=1; while [ $i -lt $r ]; do printf '\\n'; i=$((i+1)); done; printf '\\033[?1049h\\033[Hbbb'"
        )
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 2, column: 3, in: view))
        #expect(view.selectedText == String(repeating: "a", count: 2 * view.session.terminal.columns) + "\nbbb")
    }

    @Test func copiesAWrappedLineOnTheAlternateScreen() async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); printf '\\033[?1049h\\033[H'; "
                + "i=0; while [ $i -lt $((c+3)) ]; do printf b; i=$((i+1)); done"
        )
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 3, in: view))
        #expect(view.selectedText == String(repeating: "b", count: view.session.terminal.columns + 3))
    }

    @Test func extendsByLinesWhenDraggingAfterATripleClick() async throws {
        let view = try await view(running: "printf 'one\\n\\nthree\\nfour'")
        let columns = view.session.terminal.columns
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 2, in: view, clickCount: 3))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 3, column: 1, in: view))
        #expect(view.selectedText == "three\nfour")
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 1, column: 2, in: view))
        #expect(view.selection == Selection(anchor: .init(line: 2, column: columns), head: .init(line: 1, column: 0)))
    }

    @Test func extendsTheSelectionWithAShiftClick() async throws {
        let view = try await view(running: "printf 'one two three'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 7, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 4, in: view))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 13, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "two three")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "one two three")
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 8, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "three")
    }

    @Test func shrinksTheShiftClickWithAShiftDrag() async throws {
        let view = try await view(running: "printf 'one two three'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 4, in: view))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 13, in: view, modifierFlags: .shift))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 7, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "two")
    }

    @Test func extendsByLinesWithAShiftClickAfterATripleClick() async throws {
        let view = try await view(running: "printf 'one\\ntwo\\nthree four'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, clickCount: 3))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 1, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "one\ntwo\nthree four")
    }

    @Test func extendsByCharactersWithAShiftClickAfterSelectAll() async throws {
        let view = try await view(running: "printf 'one two three'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, clickCount: 3))
        view.selectAll(nil)
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 4, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "two three")
    }

    @Test func extendsByCharactersWithAShiftClickAfterFind() async throws {
        let view = try await view(running: "printf 'one two three'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, clickCount: 2))
        view.selectedRanges = [NSValue(range: (view.string as NSString).range(of: "three"))]
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 5, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "wo three")
    }

    @Test func extendsByWordsWithAShiftClickAfterADoubleClick() async throws {
        let view = try await view(running: "printf 'one two three'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 5, in: view, clickCount: 2))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 10, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "two three")
    }

    @Test func startsASelectionWithAShiftClickWithoutASelection() throws {
        let view = viewInWindow()
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 3, in: view, modifierFlags: .shift))
        #expect(view.selection == Selection(anchor: .init(line: 1, column: 3), head: .init(line: 1, column: 3)))
    }

    @Test func extendsTheTrimmedSelectionWithAShiftClick() async throws {
        let view = try await view(running: "seq 1 12000")
        let firstLine = view.session.terminal.removedScrollbackCount
        #expect(firstLine > 0)
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: firstLine + 100, column: 2))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 10, column: 1, in: view, modifierFlags: .shift))
        #expect(view.selection?.anchor == .init(line: firstLine + 100, column: 2))
    }

    @Test func extendsFromTheFartherEndOfABackwardSelectionWithAShiftClick() throws {
        let view = viewInWindow()
        let columns = view.session.terminal.columns
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 0, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 0, in: view))
        view.mouseDown(
            with: try mouseEvent(.leftMouseDown, row: 0, column: CGFloat(columns / 3), in: view, modifierFlags: .shift))
        #expect(
            view.selection == Selection(anchor: .init(line: 1, column: 0), head: .init(line: 0, column: columns / 3)))
    }

    @Test func keepsTheShiftClickWhenAShiftDragCrossesTheAnchor() async throws {
        let view = try await view(running: "printf 'one\\ntwo\\nthree'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 1, in: view, clickCount: 3))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 2, column: 1, in: view, modifierFlags: .shift))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 1, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "one\ntwo\nthree")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 1, column: 1, in: view, clickCount: 3))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 1, in: view, modifierFlags: .shift))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 2, column: 1, in: view, modifierFlags: .shift))
        #expect(view.selectedText == "one\ntwo\nthree")
    }

    @Test func drawsTheSelection() throws {
        let view = viewInWindow()
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let before = representation.colorAt(x: 40, y: 40)
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 10, column: 0))
        view.cacheDisplay(in: view.bounds, to: representation)
        #expect(representation.colorAt(x: 40, y: 40) != before)
    }

    @Test func drawsTheSelectionToTheEndOfAScrollbackLine() async throws {
        let view = try await view(running: "seq 1 50")
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        let scale = CGFloat(representation.pixelsWide) / representation.size.width
        let x = Int(view.bounds.midX * scale)
        let y = Int((4 + 1.5 * view.cellSize.height) * scale)
        view.cacheDisplay(in: view.bounds, to: representation)
        let before = representation.colorAt(x: x, y: y)
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 3, column: 0))
        view.cacheDisplay(in: view.bounds, to: representation)
        #expect(representation.colorAt(x: x, y: y) != before)
    }

    @Test func clearsTheSelectionWhenTheLinesReflow() async throws {
        let view = try await view(running: "printf 'hello world'")
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 0, in: view))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 5, in: view))
        view.fit(to: CGSize(width: 400, height: 200))
        #expect(view.selection != nil)
        view.fit(to: CGSize(width: 200, height: 200))
        #expect(view.selection == nil)
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: 0, column: 9, in: view))
        #expect(view.selection == nil)
    }

    @Test func copiesTheSelectedText() async throws {
        let view = try await view(running: "printf 'hello world   \\r\\nsecond line'")
        view.selection = Selection(anchor: .init(line: 0, column: 6), head: .init(line: 1, column: 6))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.copySelection(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "world\nsecond")
    }

    @Test func copiesAWrappedLineAsOneLine() async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); i=1; s=''; while [ $i -lt $c ]; do s=\"${s}a\"; i=$((i+1)); done; "
                + "printf '%s bc\\nnext' \"$s\""
        )
        let columns = view.session.terminal.columns
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 2, column: 4))
        #expect(view.selectedText == String(repeating: "a", count: columns - 1) + " bc\nnext")
    }

    @Test func copiesAWideCharacterThatWrapsWithoutItsPadding() async throws {
        let view = try await view(
            running:
                "c=$(stty size | cut -d' ' -f2); i=1; s=''; while [ $i -lt $c ]; do s=\"${s}a\"; i=$((i+1)); done; "
                + "printf '%s中' \"$s\""
        )
        let columns = view.session.terminal.columns
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 1, column: 2))
        #expect(view.selectedText == String(repeating: "a", count: columns - 1) + "中")
    }

    @Test func copiesWithoutTheSpacesAtTheEndOfALine() async throws {
        let view = try await view(running: "printf 'hello world   '")
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 40))
        #expect(view.selectedText == "hello world")
    }

    @Test func copiesWideCharactersOnce() async throws {
        let view = try await view(running: "printf 'a中b😀'")
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 6))
        #expect(view.selectedText == "a中b😀")
    }

    @Test func copiesFromTheScrollback() async throws {
        let view = try await view(running: "seq 1 100")
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 2, column: 0))
        #expect(view.selectedText == "1\n2\n")
    }

    @Test func copiesNothingWithoutADrag() async throws {
        let view = try await view(running: "printf 'hello'")
        view.selection = Selection(anchor: .init(line: 0, column: 2), head: .init(line: 0, column: 2))
        #expect(view.selectedText == nil)
    }

    @Test func turnsOnCopyOnlyWhenThereIsSelectedText() async throws {
        let view = try await view(running: "seq 1 12000")
        let item = NSMenuItem(title: "Copy", action: #selector(TerminalContentView.copy(_:)), keyEquivalent: "c")
        let removed = view.session.terminal.removedScrollbackCount
        let lineCount = view.session.terminal.scrollback.count + view.session.terminal.rows
        for (anchor, head) in [
            (0, 5), (removed - 5, removed - 1), (removed - 5, removed + 2), (removed + 10, removed + 10),
            (removed + lineCount - 1, removed + lineCount + 5), (removed + lineCount, removed + lineCount + 5),
        ] {
            view.selection = Selection(anchor: .init(line: anchor, column: 1), head: .init(line: head, column: 0))
            #expect(view.validateMenuItem(item) == (view.selectedText != nil), "\(anchor) \(head)")
        }
        view.selection = Selection(
            anchor: .init(line: removed - 5, column: 0), head: .init(line: removed - 1, column: 3))
        #expect(!view.validateMenuItem(item))
        view.selection = Selection(
            anchor: .init(line: removed + 3, column: 1), head: .init(line: removed + 3, column: 1))
        #expect(!view.validateMenuItem(item))
    }

    @Test func turnsOnCopyOnlyWithASelection() {
        let view = viewInWindow()
        let item = NSMenuItem(title: "Copy", action: #selector(TerminalContentView.copy(_:)), keyEquivalent: "c")
        #expect(!view.validateMenuItem(item))
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 1, column: 0))
        #expect(view.validateMenuItem(item))
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

@MainActor
private func viewInWindow() -> TerminalContentView {
    let view = TerminalContentView(session: TerminalSession(running: "exit"))
    let window = NSWindow(contentView: view)
    view.fit(to: window.frame.size)
    return view
}
