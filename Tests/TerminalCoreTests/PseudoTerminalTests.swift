import Foundation
import TerminalCore
import Testing

struct PseudoTerminalTests {
    @Test func reportsTheExitStatus() async throws {
        #expect(try await termination("exit 3") == .exit(3))
    }

    @Test func reportsAnUncaughtSignal() async throws {
        #expect(try await termination("kill -TERM $$") == .uncaughtSignal(SIGTERM))
    }

    @Test func throwsWhenTheExecutableIsMissing() {
        #expect(throws: POSIXError(.ENOENT)) {
            try PseudoTerminal(executableURL: URL(filePath: "/missing"), environment: [:], columns: 80, rows: 24)
        }
    }
}

private func termination(_ script: String) async throws -> PseudoTerminal.Termination? {
    let pseudoTerminal = try PseudoTerminal(
        executableURL: URL(filePath: "/bin/sh"),
        arguments: ["-c", script],
        environment: [:],
        columns: 80,
        rows: 24
    )
    for await event in pseudoTerminal.events {
        if case .exit(let termination) = event {
            return termination
        }
    }
    return nil
}
