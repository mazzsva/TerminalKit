import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalAccessibilityTests {
    @Test func isATextArea() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .textArea)
    }

    @Test func exposesTheScreenAsText() async throws {
        let view = try await accessibleView(running: "printf 'ab\\r\\ncd'")
        #expect(view.accessibilityValue() as? String == "ab\ncd\n")
        #expect(view.accessibilityNumberOfCharacters() == 6)
        #expect(view.accessibilityInsertionPointLineNumber() == 1)
        #expect(view.accessibilitySelectedTextRange() == NSRange(location: 5, length: 0))
    }

    @Test func includesTheScrollback() async throws {
        let view = try await accessibleView(running: "printf '1\\r\\n2\\r\\n3\\r\\n4'")
        #expect(view.accessibilityValue() as? String == "1\n2\n3\n4")
        #expect(view.accessibilityInsertionPointLineNumber() == 3)
        #expect(view.accessibilityRange(forLine: 2) == NSRange(location: 4, length: 2))
        #expect(view.accessibilityRange(forLine: 3) == NSRange(location: 6, length: 1))
        #expect(view.accessibilityRange(forLine: 4).location == NSNotFound)
        #expect(view.accessibilityLine(for: 5) == 2)
    }

    @Test func joinsAWrappedRowIntoOneLine() async throws {
        let view = try await accessibleView(running: "printf 'abcdefg'", columns: 4)
        #expect(view.accessibilityValue() as? String == "abcdefg\n")
        #expect(view.accessibilityRange(forLine: 0) == NSRange(location: 0, length: 8))
        #expect(view.accessibilityLine(for: 5) == 0)
        #expect(view.accessibilityLine(for: 8) == 1)
        #expect(view.accessibilityInsertionPointLineNumber() == 0)
        #expect(view.accessibilitySelectedTextRange() == NSRange(location: 7, length: 0))
    }

    @Test func leavesOutThePaddingOfAWideCharacterThatWraps() async throws {
        let view = try await accessibleView(running: "printf 'abc中'", columns: 4)
        #expect(view.accessibilityValue() as? String == "abc中\n")
    }

    @Test func keepsTheSpacesBeforeTheCursor() async throws {
        let view = try await accessibleView(running: "printf '$ \\r\\n'; printf '$ '")
        #expect(view.accessibilityValue() as? String == "$\n$ \n")
        #expect(view.accessibilitySelectedTextRange() == NSRange(location: 4, length: 0))
    }

    @Test func countsWideCharactersAndEmojiByTheirText() async throws {
        let view = try await accessibleView(running: "printf 'a中🙂b'")
        #expect(view.accessibilityValue() as? String == "a中🙂b\n\n")
        #expect(view.accessibilitySelectedTextRange() == NSRange(location: 5, length: 0))
        #expect(view.accessibilityRange(for: 1) == NSRange(location: 1, length: 1))
        #expect(view.accessibilityRange(for: 3) == NSRange(location: 2, length: 2))
        #expect(view.accessibilityRange(for: 5) == NSRange(location: 5, length: 1))
        #expect(view.accessibilityRange(for: 8).location == NSNotFound)
        #expect(view.accessibilityString(for: NSRange(location: 2, length: 3)) == "🙂b")
    }

    @Test func givesTheSelectedText() async throws {
        let view = try await accessibleView(running: "printf 'ab\\r\\ncd'")
        #expect(view.accessibilitySelectedText() == "")
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 1, column: 1), head: .init(line: 0, column: 1))
        #expect(view.accessibilitySelectedText() == "b\nc")
        #expect(view.accessibilitySelectedTextRange() == NSRange(location: 1, length: 3))
    }

    @Test func clampsTheRequestedRanges() async throws {
        let view = try await accessibleView(running: "printf 'ab'")
        #expect(view.accessibilityString(for: NSRange(location: 1, length: 99)) == "b\n\n")
        #expect(view.accessibilityString(for: NSRange(location: 5, length: 1)) == nil)
        #expect(view.accessibilityString(for: NSRange(location: NSNotFound, length: 0)) == nil)
        #expect(view.accessibilityAttributedString(for: NSRange(location: 0, length: 2))?.string == "ab")
        #expect(view.accessibilityLine(for: -3) == 0)
        #expect(view.accessibilityLine(for: 99) == 2)
    }

    @Test func followsTheTrimmedScrollback() async throws {
        let view = try await accessibleView(running: "seq 1 12000", rows: 2)
        let terminal = view.session.terminal
        #expect(terminal.removedScrollbackCount > 0)
        let text = try #require(view.accessibilityValue() as? String)
        #expect(text.hasPrefix("\(terminal.removedScrollbackCount + 1)\n"))
        #expect(text.hasSuffix("11999\n12000\n"))

        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: terminal.removedScrollbackCount + 1, column: 1))
        #expect(view.accessibilitySelectedTextRange().location == 0)
    }

    @Test func updatesTheTextAfterNewOutput() async throws {
        let session = TerminalSession(running: "printf a; read x; printf b")
        session.resize(columns: 10, rows: 1)
        let view = TerminalContentView(session: session)
        try session.start()
        await session.waitForText("a")
        #expect(view.accessibilityValue() as? String == "a")

        session.send(Array("\r".utf8))
        await session.waitForExit()
        #expect(view.accessibilityValue() as? String == "a\nb")
    }

    @Test func reusesTheScrollbackOnlyWhileItStaysTheSame() async throws {
        let session = TerminalSession(running: "stty -echo; while IFS= read -r line; do printf \"$line\"; done")
        session.resize(columns: 6, rows: 2)
        let view = TerminalContentView(session: session)
        try session.start()
        var generator = SystemRandomNumberGenerator()
        let pieces = [
            "abc", "中文字", "x\\r\\n", "\\r\\n", "a long line\\r\\n", "\u{1B}[3J", "\u{1B}c", "\u{1B}[2J", "e\u{301}",
        ]
        for step in 0 ..< 80 {
            let marker = "#\(step)#"
            session.send(Array("\(pieces.randomElement(using: &generator) ?? "")\(marker)\n".utf8))
            for await text in Observations({
                TerminalContentView.AccessibilityText(session.terminal, revision: 0).string
            })
            where text.contains(marker) {
                break
            }
            if step % 3 == 0 {
                session.resize(columns: [1, 2, 6, 9].randomElement(using: &generator) ?? 6, rows: 2)
            }
            let fresh = TerminalContentView.AccessibilityText(session.terminal, revision: 0)
            #expect(view.accessibilityValue() as? String == fresh.string)
            #expect(view.accessibilityText.rows == fresh.rows)
            #expect(view.accessibilityText.lines == fresh.lines)
        }
        session.send([4])
        await session.waitForExit()
    }

    @Test func placesTheInsertionPointOnTheCursor() async throws {
        let view = try await accessibleView(running: "printf 'a中b\\b\\b\\b'")
        let window = NSWindow(contentView: view)
        let range = view.accessibilitySelectedTextRange()
        #expect(range == NSRange(location: 1, length: 0))
        let cursor = window.convertToScreen(view.convert(view.cursorRect, to: nil))
        #expect(view.accessibilityFrame(for: range) == cursor)
        #expect(cursor.width == 2 * view.cellSize.width)
    }

    @Test func framesARangeAcrossRows() async throws {
        let view = try await accessibleView(running: "printf 'ab\\r\\ncd'")
        let window = NSWindow(contentView: view)
        let frame = view.accessibilityFrame(for: NSRange(location: 1, length: 3))
        let expected = view.rect(row: 0, columns: 1 ..< 10).union(view.rect(row: 1, columns: 0 ..< 1))
        #expect(frame == window.convertToScreen(view.convert(expected, to: nil)))
        #expect(view.accessibilityFrame(for: NSRange(location: 99, length: 1)) == .zero)
    }

    @Test func framesTheEndOfAFullRow() async throws {
        let view = try await accessibleView(running: "printf '0123456789\\r\\nx'")
        let window = NSWindow(contentView: view)
        let frame = view.accessibilityFrame(for: NSRange(location: 10, length: 0))
        #expect(frame == window.convertToScreen(view.convert(view.rect(row: 0, columns: 9 ..< 10), to: nil)))
    }

    @Test func findsTheCharacterAtAPoint() async throws {
        let view = try await accessibleView(running: "printf 'ab\\r\\ncd'")
        let window = NSWindow(contentView: view)
        let cell = view.rect(row: 1, columns: 1 ..< 2)
        let point = window.convertPoint(toScreen: view.convert(CGPoint(x: cell.midX, y: cell.midY), to: nil))
        #expect(view.accessibilityRange(for: point) == NSRange(location: 4, length: 1))
    }

    @Test func givesTheVisibleText() async throws {
        let session = TerminalSession(running: "printf '1\\r\\n2\\r\\n3\\r\\n4\\r\\n5'")
        let scrollView = TerminalScrollView(session: session)
        let view = scrollView.terminalView
        let window = NSWindow(contentView: scrollView)
        window.setContentSize(CGSize(width: 200, height: 2 * view.cellSize.height + 8))
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(view.accessibilityVisibleCharacterRange() == NSRange(location: 6, length: 3))

        view.scroll(.zero)
        #expect(view.accessibilityVisibleCharacterRange() == NSRange(location: 0, length: 3))
    }

    @Test func throttlesTheChangeNotifications() async throws {
        let view = try await accessibleView(running: "printf a")
        var posts = 0
        view.postAccessibilityNotifications = { _ in posts += 1 }
        #expect(!view.isAccessibilityNotificationScheduled)
        try draw(view)
        #expect(view.isAccessibilityNotificationScheduled)
        try draw(view)
        view.scheduleAccessibilityNotification()
        view.scheduleAccessibilityNotification()
        await waitForNotification(of: view)
        #expect(posts == 1)

        try draw(view)
        #expect(!view.isAccessibilityNotificationScheduled)
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 0), head: .init(line: 0, column: 1))
        #expect(view.isAccessibilityNotificationScheduled)
        await waitForNotification(of: view)
        #expect(posts == 2)
    }
}

@MainActor
private func accessibleView(running script: String, columns: Int = 10, rows: Int = 3) async throws
    -> TerminalContentView
{
    let session = TerminalSession(running: script)
    session.resize(columns: columns, rows: rows)
    let view = TerminalContentView(session: session)
    view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
    try session.start()
    await session.waitForExit()
    return view
}

@MainActor
private func draw(_ view: NSView) throws {
    view.cacheDisplay(in: view.bounds, to: try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds)))
}

@MainActor
private func waitForNotification(of view: TerminalContentView) async {
    while view.isAccessibilityNotificationScheduled {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
