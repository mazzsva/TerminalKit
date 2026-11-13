import Testing

@testable import TerminalCore

struct ProgramStatusTests {
    @Test(arguments: ["\u{7}", "\u{1B}\\"])
    func answersTheQuery(terminator: String) {
        var terminal = Terminal(columns: 20, rows: 5)
        #expect(terminal.receive("\u{1B}]7501;?\(terminator)") == "\u{1B}]7501;?\u{7}")
        #expect(terminal.programStatus == nil)
    }

    @Test(arguments: [
        ("idle", Terminal.ProgramStatus.State.idle), ("working", .working), ("done", .done),
    ])
    func setsTheReportedState(name: String, state: Terminal.ProgramStatus.State) {
        var terminal = Terminal(columns: 20, rows: 5)
        #expect(terminal.receive("\u{1B}]7501;state=\(name):app=claude-code\u{7}") == "")
        #expect(terminal.programStatus == .init(state: state, application: "claude-code"))
    }

    @Test(arguments: ["\u{7}", "\u{1B}\\"])
    func setsTheBlockedStateWithItsMessage(terminator: String) {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive(
            "\u{1B}]7501;state=blocked:app=claude-code:kind=permission:msg=YXBwcm92ZSBXcml0ZTogbm90ZS50eHQ=\(terminator)"
        )
        #expect(
            terminal.programStatus
                == .init(
                    state: .blocked, application: "claude-code", kind: "permission",
                    message: "approve Write: note.txt"))
    }

    @Test func clearsTheStatus() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7501;state=working:app=claude-code\u{7}\u{1B}]7501;state=clear\u{7}")
        #expect(terminal.programStatus == nil)
    }

    @Test func keepsTheStatusForAnUnknownState() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7501;state=working:app=claude-code\u{7}")
        terminal.receive("\u{1B}]7501;state=sleeping:app=other\u{7}\u{1B}]7501;app=other\u{7}")
        #expect(terminal.programStatus == .init(state: .working, application: "claude-code"))
    }

    @Test func ignoresUnknownKeys() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7501;id=7:state=done:progress=40:title=t:flag\u{7}")
        #expect(terminal.programStatus == .init(state: .done))
    }

    @Test func dropsTheControlCharactersOfTheMessage() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7501;state=blocked:msg=YRtbMzFtYgdjf2QJZQ==\u{7}")
        #expect(terminal.programStatus?.message == "a[31mbcde")
    }

    @Test(arguments: ["//4=", "not base64"])
    func keepsTheReportWithAMessageThatDoesNotDecode(message: String) {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7501;state=blocked:kind=permission:msg=\(message)\u{7}")
        #expect(terminal.programStatus == .init(state: .blocked, kind: "permission"))
    }

    @Test func keepsTheStatusAfterAReset() {
        var terminal = Terminal(columns: 20, rows: 5)
        terminal.receive("\u{1B}]7501;state=done:app=claude-code\u{7}\u{1B}c")
        #expect(terminal.programStatus == .init(state: .done, application: "claude-code"))
    }
}

extension Terminal.ProgramStatus {
    init(state: State, application: String? = nil, kind: String? = nil) {
        self.init(state: state, application: application, kind: kind, message: nil)
    }
}
