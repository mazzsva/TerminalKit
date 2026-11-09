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
                head -c 31 | tr '\\033' E
                """
        )
        let view = TerminalContentView(session: session)
        session.sizingView = view
        try session.start()
        #expect(await session.linesAfterExit().contains("pE]11;rgb:213d/2743/33e7E[?1;2c"))
    }
}
