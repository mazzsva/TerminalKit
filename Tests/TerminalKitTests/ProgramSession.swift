import Foundation
import Testing

@testable import TerminalCore
@testable import TerminalKit

@MainActor
final class ProgramSession {
    enum Key: String {
        case up = "A"
        case left = "D"
    }

    struct Timeout: Error {}

    let folder = URL.temporaryDirectory.appending(path: "ProgramSession-" + UUID().uuidString)
    private(set) var terminal = Terminal(columns: 80, rows: 24)
    private(set) var output: [UInt8] = []
    private(set) var isFinished = false
    private var pseudoTerminal: PseudoTerminal?

    init() throws {
        for name in ["home", "zdot", "work"] {
            try FileManager.default.createDirectory(at: url(name), withIntermediateDirectories: true)
        }
        try write("export HOME='\(url("home").path(percentEncoded: false))'\ncd\n", to: "zdot/.zshenv")
        try write("PS1='%# '\n", to: "zdot/.zshrc")
        let gray = Terminal.RGB(red: 0x8000, green: 0x8000, blue: 0x8000)
        terminal.defaultColors = Terminal.DefaultColors(foreground: gray, background: gray, cursor: gray)
    }

    var lines: [String] {
        terminal.screen.map { line in
            let text = line.filter { $0.width != 0 }.map { $0.isTab || $0.isTabGap ? " " : terminal.character(of: $0) }
            return String(text.joined().reversed().drop { $0 == " " }.reversed())
        }
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

    func url(_ name: String) -> URL {
        folder.appending(path: name)
    }

    func write(_ text: String, to name: String) throws {
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

    func press(_ key: Key) {
        send((terminal.usesApplicationCursorKeys ? "\u{1B}O" : "\u{1B}[") + key.rawValue)
    }

    func wait(_ condition: (ProgramSession) -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(self) {
            guard !isFinished, ContinuousClock.now < deadline else {
                Issue.record("Screen:\n\(lines.joined(separator: "\n"))", sourceLocation: sourceLocation)
                throw Timeout()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func exit(sourceLocation: SourceLocation = #_sourceLocation) async throws -> PseudoTerminal.Termination? {
        try await wait({ $0.isFinished }, sourceLocation: sourceLocation)
        return pseudoTerminal?.termination
    }

    func close() {
        pseudoTerminal?.hangUp()
        try? FileManager.default.removeItem(at: folder)
    }
}
