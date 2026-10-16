import Foundation
import TerminalCore
import Testing

struct PseudoTerminalTests {
    @Test func startsAProcess() throws {
        let pseudoTerminal = try PseudoTerminal(
            executableURL: URL(filePath: "/usr/bin/true"),
            environment: [:],
            columns: 80,
            rows: 24
        )
        #expect(pseudoTerminal.processIdentifier > 0)
    }

    @Test func throwsWhenTheExecutableIsMissing() {
        #expect(throws: POSIXError(.ENOENT)) {
            try PseudoTerminal(executableURL: URL(filePath: "/missing"), environment: [:], columns: 80, rows: 24)
        }
    }
}
