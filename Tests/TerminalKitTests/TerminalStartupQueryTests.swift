import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalStartupQueryTests {
    @Test func answersTheStartupQueriesInOrder() async throws {
        let session = TerminalSession(
            running: """
                stty raw -echo; printf '\\033[?2026$p\\033[?u\\033]11;?\\033\\\\\\033[c'; \
                head -c 37 | tr '\\033' E
                """
        )
        let view = TerminalContentView(session: session)
        view.appearance = NSAppearance(named: .darkAqua)
        session.sizingView = view
        try session.start()
        #expect(await session.linesAfterExit().contains("E[?0uE]11;rgb:1e1e/1e1e/1e1eE\\E[?1;2c"))
    }
}
