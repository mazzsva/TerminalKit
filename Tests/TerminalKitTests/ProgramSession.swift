import AppKit
import Testing

@testable import TerminalCore
@testable import TerminalKit

actor ProgramSession {
    enum Key: String {
        case up = "A"
        case down = "B"
        case left = "D"
    }

    struct Timeout: Error {}

    let folder = URL.temporaryDirectory.appending(path: "ProgramSession-" + UUID().uuidString)
    private(set) var terminal = {
        var terminal = Terminal(columns: 80, rows: 24)
        let gray = Terminal.RGB(red: 0x8000, green: 0x8000, blue: 0x8000)
        terminal.defaultColors = Terminal.DefaultColors(foreground: gray, background: gray, cursor: gray)
        return terminal
    }()
    private(set) var output: [UInt8] = []
    private(set) var isFinished = false
    private var pseudoTerminal: PseudoTerminal?

    init() throws {
        for name in ["home", "zdot", "work"] {
            try FileManager.default.createDirectory(at: url(name), withIntermediateDirectories: true)
        }
        try write("export HOME='\(url("home").path(percentEncoded: false))'\ncd\n", to: "zdot/.zshenv")
        try write("PS1='%# '\n", to: "zdot/.zshrc")
    }

    var lines: [String] {
        terminal.screen.map(text(of:))
    }

    var scrollbackLines: [String] {
        terminal.scrollback.map(text(of:))
    }

    var cursor: Terminal.Position {
        terminal.cursor
    }

    var controlFunctions: Set<String> {
        var parser = EscapeSequenceParser()
        var names: Set<String> = []
        for scalar in String(decoding: output, as: UTF8.self).unicodeScalars {
            switch parser.advance(scalar) {
            case .execute(let control):
                names.insert(String(format: "C0 %02X", control.value))
            case .escape(let intermediates, let final):
                names.insert("ESC \(intermediates)\(final)")
            case .controlSequence(let sequence):
                let prefix = "CSI \(sequence.privateMarker.map(String.init) ?? "")"
                let suffix = "\(sequence.intermediates)\(sequence.final)"
                let parameters =
                    "hl".unicodeScalars.contains(sequence.final)
                    ? sequence.parameters
                    : "mnt".unicodeScalars.contains(sequence.final) ? Array(sequence.parameters.prefix(1)) : []
                names.formUnion(parameters.isEmpty ? [prefix + suffix] : parameters.map { prefix + "\($0)" + suffix })
            case .operatingSystemCommand(let command):
                names.insert("OSC " + command.prefix { $0 != ";" })
            default:
                break
            }
        }
        return names
    }

    nonisolated func url(_ name: String) -> URL {
        folder.appending(path: name)
    }

    nonisolated func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: url(name))
    }

    func start(_ command: [String] = [], environment: [String: String] = [:]) throws {
        var configuration = TerminalSession.Configuration.loginShell(
            inheriting: environment.merging(["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]) { $1 }
                .merging(["HOME": "home", "ZDOTDIR": "zdot"].mapValues { url($0).path(percentEncoded: false) }) { $1 }
        )
        if !command.isEmpty {
            configuration.executableURL = URL(filePath: command[0])
            configuration.arguments = Array(command.dropFirst())
            configuration.currentDirectoryURL = url("work")
        }
        try start(configuration)
    }

    func start(_ configuration: TerminalSession.Configuration) throws {
        let pseudoTerminal = try PseudoTerminal(
            executableURL: configuration.executableURL,
            arguments: configuration.arguments,
            environment: configuration.environment,
            currentDirectoryURL: configuration.currentDirectoryURL,
            columns: terminal.columns,
            rows: terminal.rows
        )
        self.pseudoTerminal = pseudoTerminal
        Task {
            for await bytes in pseudoTerminal.output {
                output += bytes
                let replies = terminal.receive(bytes)
                if !replies.isEmpty {
                    pseudoTerminal.write(replies, isReply: true)
                }
            }
            isFinished = true
        }
    }

    func send(_ text: String) {
        pseudoTerminal?.write(Array(text.utf8))
    }

    func pressShiftReturn() throws {
        let event = try keyDown("\r", modifierFlags: .shift)
        let input =
            event.otherKeyInput(level: terminal.modifyOtherKeys, usesOptionAsMetaKey: false).map(TerminalKeyInput.bytes)
            ?? event.terminalKeyInput(TerminalKeyModes())
        if case .bytes(let bytes) = input {
            pseudoTerminal?.write(bytes)
        }
    }

    func paste(_ text: String) async {
        let bytes = await TerminalSession.pastedBytes(text, isBracketed: terminal.usesBracketedPaste)
        pseudoTerminal?.write(bytes ?? [])
    }

    func resize(columns: Int, rows: Int) {
        terminal.resize(columns: columns, rows: rows)
        pseudoTerminal?.resize(columns: columns, rows: rows)
    }

    func press(_ key: Key) {
        send((terminal.usesApplicationCursorKeys ? "\u{1B}O" : "\u{1B}[") + key.rawValue)
    }

    func wait(
        timeout: Duration = .seconds(10),
        _ condition: @Sendable (isolated ProgramSession) -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(self) {
            guard !isFinished, ContinuousClock.now < deadline else {
                Issue.record(
                    "Cursor \(cursor), screen:\n\(lines.joined(separator: "\n"))", sourceLocation: sourceLocation)
                throw Timeout()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func exit(sourceLocation: SourceLocation = #_sourceLocation) async throws -> PseudoTerminal.Termination? {
        try await wait({ $0.isFinished }, sourceLocation: sourceLocation)
        return pseudoTerminal?.termination
    }

    private func text(of line: Terminal.Line) -> String {
        let text = line.filter { $0.width != 0 }.map { $0.isTab || $0.isTabGap ? " " : terminal.character(of: $0) }
        return String(text.joined().reversed().drop { $0 == " " }.reversed())
    }

    func close() {
        pseudoTerminal?.hangUp()
        try? FileManager.default.removeItem(at: folder)
    }
}
