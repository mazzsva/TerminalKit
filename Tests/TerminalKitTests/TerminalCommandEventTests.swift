import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalCommandEventTests {
    private func summary(of events: [TerminalSession.CommandEvent]) -> [String] {
        events.map { event in
            switch event {
            case .started(let command):
                "started \(command.id) \(command.text ?? "") \(command.endDate == nil)"
            case .finished(let command):
                "finished \(command.id) \(command.text ?? "") \(command.exitStatus.map(String.init) ?? "none") \(command.endDate != nil)"
            }
        }
    }

    private func events(of stream: AsyncStream<TerminalSession.CommandEvent>) -> Task<[String], Never> {
        Task {
            var events: [TerminalSession.CommandEvent] = []
            for await event in stream {
                events.append(event)
            }
            return summary(of: events)
        }
    }

    private func value(of task: Task<[String], Never>) async -> [String] {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @Test func sendsTheStartAndTheEndOfEachCommand() async throws {
        let session = TerminalSession(
            running: """
                printf '\\033]133;C;cmdline_url=a\\007\\033]133;D;0\\007\\033]133;C;cmdline_url=b\\007'
                read line
                printf '\\033]133;D;3\\007'
                """
        )
        let first = events(of: session.commandEvents())
        let second = events(of: session.commandEvents())
        try session.start()
        await session.waitForCommands { $0.count == 2 }
        session.send("\r")
        let expected = ["started 0 a true", "finished 0 a 0 true", "started 1 b true", "finished 1 b 3 true"]
        #expect(await value(of: first) == expected)
        #expect(await value(of: second) == expected)
    }

    @Test func finishesARunningCommandWhenTheProcessExits() async throws {
        let session = TerminalSession(running: "printf '\\033]133;C;cmdline_url=sleep\\007'; exit 5")
        let events = events(of: session.commandEvents())
        try session.start()
        #expect(await value(of: events) == ["started 0 sleep true", "finished 0 sleep none true"])
        #expect(session.state == .exited(.exit(5)))
    }

    @Test func endsTheEventsOfAnExitedSession() async throws {
        let session = TerminalSession(running: "exit")
        try session.start()
        await session.waitForExit()
        #expect(await value(of: events(of: session.commandEvents())).isEmpty)
    }
}
