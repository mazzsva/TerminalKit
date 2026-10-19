import Foundation
import TerminalKit
import Testing

@MainActor
struct TerminalPublicAPITests {
    @Test func makesACommandForAPreview() throws {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let command = TerminalSession.Command(
            id: 3,
            text: "ls",
            directory: URL(filePath: "/tmp"),
            exitStatus: 1,
            startDate: date,
            endDate: date.addingTimeInterval(2)
        )
        #expect(command.id == 3)
        #expect(command.text == "ls")
        #expect(command.directory == URL(filePath: "/tmp"))
        #expect(command.exitStatus == 1)
        #expect(command.endDate == date.addingTimeInterval(2))
        let running = TerminalSession.Command(id: 4, text: nil, startDate: date)
        #expect(running.directory == nil)
        #expect(running.exitStatus == nil)
        #expect(running.endDate == nil)
        let decoded = try JSONDecoder().decode(TerminalSession.Command.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }
}
