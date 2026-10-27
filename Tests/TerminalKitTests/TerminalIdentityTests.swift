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

    @Test nonisolated func identifiesASessionOffTheMainActor() async {
        let first = await TerminalSession(running: "exit")
        let second = await TerminalSession(running: "exit")
        #expect(Set([first, second, first]).count == 2)
        #expect(Set([Selection.terminal(first), .terminal(second), .terminal(first)]).count == 2)
    }

    @Test func hashesTheStates() {
        let states: Set<TerminalSession.State> = [.idle, .running, .exited(.exit(0)), .exited(.uncaughtSignal(1))]
        #expect(states.count == 4)
    }
}

private enum Selection: Hashable {
    case terminal(TerminalSession)
}
