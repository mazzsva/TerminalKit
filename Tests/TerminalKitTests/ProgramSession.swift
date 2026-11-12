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

    struct Event: Codable, Equatable {
        var output: [String]?
        var columns: Int?
        var rows: Int?
        var screen: [String]?
        var cursor: [Int]?
    }

    let folder = URL.temporaryDirectory.appending(path: "ProgramSession-" + UUID().uuidString)
    private(set) var terminal = newTerminal()
    private(set) var output: [UInt8] = []
    private(set) var events: [(offset: Int, event: Event)] = []
    private(set) var isFinished = false
    private var pseudoTerminal: PseudoTerminal?

    init() throws {
        for name in ["home", "zdot", "work"] {
            try FileManager.default.createDirectory(at: url(name), withIntermediateDirectories: true)
        }
        try write("export HOME='\(url("home").path(percentEncoded: false))'\ncd\n", to: "zdot/.zshenv")
        try write("PS1='%# '\n", to: "zdot/.zshrc")
    }

    static func newTerminal() -> Terminal {
        var terminal = Terminal(columns: 80, rows: 24)
        let gray = Terminal.RGB(red: 0x8000, green: 0x8000, blue: 0x8000)
        terminal.defaultColors = Terminal.DefaultColors(foreground: gray, background: gray, cursor: gray)
        return terminal
    }

    var lines: [String] {
        Self.lines(of: terminal)
    }

    var scrollbackLines: [String] {
        terminal.scrollback.map { Self.text(of: $0, in: terminal) }
    }

    var cursor: Terminal.Position {
        terminal.cursor
    }

    var controlFunctions: Set<String> {
        Self.controlFunctions(in: output)
    }

    static func controlFunctions(in output: [UInt8]) -> Set<String> {
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
                let units = Self.units(of: sequence)
                names.formUnion(units.isEmpty ? [prefix + suffix] : units.map { prefix + $0 + suffix })
            case .operatingSystemCommand(let command):
                let number = command.prefix { $0 != ";" }
                let isQuery = ["4", "10", "11", "12"].contains(number) && command.split(separator: ";").contains("?")
                names.insert("OSC " + number + (isQuery ? ";?" : ""))
            default:
                break
            }
        }
        return names
    }

    private static func units(of sequence: EscapeSequenceParser.ControlSequence) -> [String] {
        let parameters = sequence.parameters.indices.map { index in
            "\(sequence.parameters[index])" + (sequence.subparameters[index].map { ":\($0)" } ?? "")
        }
        let isPlain = sequence.privateMarker == nil && sequence.intermediates.isEmpty
        switch sequence.final {
        case "m" where isPlain:
            return graphicRenditionUnits(of: sequence, names: parameters)
        case "h", "l":
            return parameters
        case "m" where sequence.privateMarker == ">", "t" where ["22", "23"].contains(parameters.first):
            return [parameters.prefix(2).joined(separator: ";")]
        case "c", "J", "K", "m", "n", "t":
            return Array(parameters.prefix(1))
        default:
            return sequence.subparameters.isEmpty ? [] : [parameters.joined(separator: ";")]
        }
    }

    private static func graphicRenditionUnits(
        of sequence: EscapeSequenceParser.ControlSequence,
        names: [String]
    ) -> [String] {
        let values = sequence.parameters.indices.map {
            sequence.subparameters[$0] == nil ? sequence.parameters[$0] : -1
        }
        var units: [String] = []
        var index = 0
        while index < values.count {
            guard [38, 48, 58].contains(values[index]), index + 1 < values.count else {
                units.append(names[index])
                index += 1
                continue
            }
            let length = [5: 1, 2: 3][values[index + 1]] ?? 0
            let colors = values.dropFirst(index + 2).prefix(length)
            let isComplete = length > 0 && colors.count == length && colors.allSatisfy { (0 ... 255).contains($0) }
            units.append(isComplete ? "\(values[index]);\(values[index + 1])" : "\(values[index])")
            index += 2 + length
        }
        return units
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
        events.append((output.count, Event(columns: columns, rows: rows)))
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
        events.append((output.count, Self.checkpoint(terminal)))
    }

    func exit(sourceLocation: SourceLocation = #_sourceLocation) async throws -> PseudoTerminal.Termination? {
        try await wait({ $0.isFinished }, sourceLocation: sourceLocation)
        return pseudoTerminal?.termination
    }

    static func checkpoint(_ terminal: Terminal) -> Event {
        Event(screen: lines(of: terminal), cursor: [terminal.cursor.row, terminal.cursor.column])
    }

    static func lines(of terminal: Terminal) -> [String] {
        terminal.screen.map { text(of: $0, in: terminal) }
    }

    private static func text(of line: Terminal.Line, in terminal: Terminal) -> String {
        let text = line.filter { $0.width != 0 }.map { $0.isTab || $0.isTabGap ? " " : terminal.character(of: $0) }
        return String(text.joined().reversed().drop { $0 == " " }.reversed())
    }

    func close() {
        pseudoTerminal?.hangUp()
        try? FileManager.default.removeItem(at: folder)
    }
}
