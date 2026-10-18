import Foundation
import Testing

@testable import TerminalKit

@MainActor
struct TerminalIdentityTests {
    @Test func identifiesASessionByItsObject() {
        let first = TerminalSession(running: "exit")
        let second = TerminalSession(running: "exit")
        #expect(first == first)
        #expect(first != second)
        #expect(first.id == ObjectIdentifier(first))
        #expect(Set([first, second, first]).count == 2)
        #expect([first: 1, second: 2][second] == 2)
    }

    @Test func hashesTheStatesAndCommands() {
        let states: Set<TerminalSession.State> = [.idle, .running, .exited(.exit(0)), .exited(.uncaughtSignal(1))]
        #expect(states.count == 4)
        let command = TerminalSession.Command(
            id: 1,
            text: "ls",
            directory: URL(filePath: "/tmp"),
            exitStatus: 0,
            startDate: .distantPast,
            endDate: .distantFuture
        )
        var other = command
        other.exitStatus = 1
        #expect(Set([command, command, other]).count == 2)
    }
}
