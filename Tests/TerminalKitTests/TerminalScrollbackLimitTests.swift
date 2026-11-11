import AppKit
import Foundation
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalScrollbackLimitTests {
    @Test func keepsTheTextInPlaceWhenTheOldestLinesGo() async throws {
        let session = TerminalSession(running: "seq 1 100000; read line; seq 100001 100500")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        try session.start()
        await session.waitForText("100000")
        scrollView.layoutSubtreeIfNeeded()
        let view = scrollView.terminalView
        view.scroll(CGPoint(x: 0, y: TerminalContentView.topPadding + 50_000 * view.cellSize.height))
        let text = topLine(in: scrollView)
        session.send(Array("\r".utf8))
        await session.waitForExit()
        scrollView.layoutSubtreeIfNeeded()
        #expect(session.terminal.removedScrollbackCount > 0)
        #expect(session.terminal.scrollback.count == 100_000)
        #expect(text == "50001")
        #expect(topLine(in: scrollView) == text)
    }

    private func topLine(in scrollView: TerminalScrollView) -> String {
        let view = scrollView.terminalView
        let terminal = view.session.terminal
        let row = Int(
            ((scrollView.contentView.bounds.minY - TerminalContentView.topPadding) / view.cellSize.height).rounded())
        return terminal.scrollback[row].map(terminal.character(of:)).joined()
    }
}
