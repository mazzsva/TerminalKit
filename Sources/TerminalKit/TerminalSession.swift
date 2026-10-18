import Observation
import TerminalCore

@MainActor
@Observable
public final class TerminalSession {
    public enum State: Equatable, Sendable {
        case idle
        case running
        case exited
    }

    public let configuration: Configuration
    public private(set) var state = State.idle

    private(set) var terminal = Terminal(columns: 80, rows: 24)

    @ObservationIgnored private var pseudoTerminal: PseudoTerminal?

    public init(configuration: Configuration = .loginShell) {
        self.configuration = configuration
    }

    public func start() throws {
        guard state == .idle else {
            return
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
        state = .running

        let output = pseudoTerminal.output
        Task { [weak self] in
            for await bytes in output {
                self?.receive(bytes)
            }
            self?.state = .exited
            self?.pseudoTerminal = nil
        }
    }

    func resize(columns: Int, rows: Int) {
        guard columns != terminal.columns || rows != terminal.rows else {
            return
        }
        terminal.resize(columns: columns, rows: rows)
        pseudoTerminal?.resize(columns: columns, rows: rows)
    }

    func send(_ bytes: [UInt8]) {
        pseudoTerminal?.write(bytes)
    }

    private func receive(_ bytes: [UInt8]) {
        let replies = terminal.receive(bytes)
        if !replies.isEmpty {
            pseudoTerminal?.write(replies)
        }
    }
}
