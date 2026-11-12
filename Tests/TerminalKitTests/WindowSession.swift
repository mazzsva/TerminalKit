import AppKit
import SwiftUI
import Testing

@testable import TerminalCore
@testable import TerminalKit

@MainActor
final class WindowSession {
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: [.titled, .resizable],
        backing: .buffered,
        defer: false
    )
    private var session = TerminalSession()

    var terminal: Terminal {
        session.terminal
    }

    private var view: TerminalContentView? {
        window.firstResponder as? TerminalContentView
    }

    func start(_ configuration: TerminalSession.Configuration) throws {
        session = TerminalSession(configuration: configuration)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TerminalView(session: session))
        window.orderBack(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try #require(view != nil)
        resize(columns: 80, rows: 24)
        try session.start()
    }

    func send(_ text: String) {
        let codes: [Character: UInt16] = ["\r": 36, "\u{1B}": 53, "\u{7F}": 51, "\u{3}": 8]
        for character in text {
            key(String(character), code: codes[character] ?? 0, flags: character == "\u{3}" ? .control : [])
        }
    }

    func press(_ key: ProgramSession.Key) {
        let (character, code) = [.up: (0xF700, 126), .down: (0xF701, 125), .left: (0xF702, 123)][key] ?? (0, 0)
        self.key(String(UnicodeScalar(UInt16(character)) ?? " "), code: UInt16(code), flags: [.function, .numericPad])
    }

    func pressShiftReturn() {
        key("\r", code: 36, flags: .shift)
    }

    private func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            )
            .map(window.sendEvent)
        }
    }

    func paste(_ text: String) {
        session.paste(text)
    }

    func resize(columns: Int, rows: Int) {
        guard let view, let scrollView = view.enclosingScrollView else {
            return
        }
        let padding = TerminalContentView.topPadding + TerminalContentView.bottomPadding
        window.setContentSize(
            CGSize(
                width: window.contentLayoutRect.width - scrollView.contentSize.width + 2 * TerminalContentView.padding
                    + CGFloat(columns) * view.cellSize.width + 0.5,
                height: window.contentLayoutRect.height - scrollView.contentSize.height + padding
                    + CGFloat(rows) * view.cellSize.height + 0.5
            ))
    }

    func scrollsBack(to line: @Sendable (String) -> Bool) async throws -> Bool {
        let isShown = try await scroll(lines: 10) { $0.contains(where: line) }
        let isAtBottom = try await scroll(lines: -10) { _ in
            view.map { NSMaxRange($0.accessibilityVisibleCharacterRange()) == $0.accessibilityNumberOfCharacters() }
                ?? false
        }
        return isShown && isAtBottom
    }

    private func scroll(lines: Int32, until condition: ([String]) -> Bool) async throws -> Bool {
        let cgEvent = try #require(scrollWheelEvent(lines: lines).cgEvent)
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        cgEvent.location = CGPoint(x: window.frame.midX, y: screenHeight - window.frame.midY)
        for field in [91, 92].compactMap(CGEventField.init) {
            cgEvent.setIntegerValueField(field, value: Int64(window.windowNumber))
        }
        let event = try #require(NSEvent(cgEvent: cgEvent))
        for _ in 0 ..< 50 where !condition(visibleLines) {
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(200))
        }
        try await Task.sleep(for: .seconds(1))
        return condition(visibleLines)
    }

    private var visibleLines: [String] {
        guard let view, let text = view.accessibilityValue() as? NSString else {
            return []
        }
        return text.substring(with: view.accessibilityVisibleCharacterRange()).components(separatedBy: "\n")
    }

    func waitForScreen(
        _ timeout: Duration,
        _ condition: @Sendable (Terminal) -> Bool,
        _ sourceLocation: SourceLocation
    ) async throws {
        guard try await poll(timeout, until: { condition(terminal) }) else {
            let screen = ProgramSession.lines(of: terminal).joined(separator: "\n")
            Issue.record("Screen:\n\(screen)", sourceLocation: sourceLocation)
            throw ProgramSession.Timeout()
        }
    }

    func exitedTerminal() async throws -> Terminal? {
        try await poll(.seconds(10)) { session.state != .running } && session.state == .exited(.exit(0))
            ? terminal : nil
    }

    private func poll(_ timeout: Duration, until isDone: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !isDone(), session.state == .running, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return isDone()
    }

    func close() {
        session.terminate()
        window.close()
    }
}

extension WindowSession: ClaudeSession {}
