import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
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

    @Test func drawsTheSelection() throws {
        let view = viewInWindow()
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let before = representation.colorAt(x: 40, y: 40)
        view.selection = Selection(anchor: .init(line: 0, column: 0), head: .init(line: 10, column: 0))
        view.cacheDisplay(in: view.bounds, to: representation)
        #expect(representation.colorAt(x: 40, y: 40) != before)
    }

    @Test func copiesTheSelectedText() async throws {
        let view = try await view(running: "printf 'hello world   \\r\\nsecond line'")
        view.selection = Selection(anchor: .init(line: 0, column: 6), head: .init(line: 1, column: 6))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.copySelection(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "world\nsecond")
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
    let session = TerminalSession(
        configuration: .init(executableURL: URL(filePath: "/bin/sh"), arguments: ["-c", script])
    )
    let view = TerminalContentView(session: session)
    view.fit(to: CGSize(width: 400, height: 300))
    try session.start()
    for await state in Observations({ session.state }) where state != .running {
        break
    }
    return view
}

@MainActor
private func viewInWindow() -> TerminalContentView {
    let view = TerminalContentView(
        session: TerminalSession(configuration: .init(executableURL: URL(filePath: "/bin/sh"))))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [],
        backing: .buffered,
        defer: true
    )
    window.contentView = view
    view.fit(to: CGSize(width: 400, height: 300))
    return view
}

@MainActor
private func mouseEvent(_ type: NSEvent.EventType, row: Int, column: Int, in view: TerminalContentView) throws
    -> NSEvent
{
    let point = CGPoint(
        x: TerminalContentView.padding + CGFloat(column) * view.cellSize.width,
        y: TerminalContentView.padding + (CGFloat(row) + 0.5) * view.cellSize.height
    )
    return try #require(
        NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    )
}
