import Observation
import TerminalCore

@MainActor
@Observable
public final class TerminalSession {
    public enum State: Equatable, Sendable {
        case idle
        case running
        case exited(Termination)
    }

    public enum Termination: Equatable, Sendable {
        case exit(Int32)
        case uncaughtSignal(Int32)
    }

    private let configuration: Configuration
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
            self?.finish()
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

    private func finish() {
        guard let termination = pseudoTerminal?.termination else {
            return
        }
        state = .exited(Termination(termination))
        pseudoTerminal = nil
    }

    private func receive(_ bytes: [UInt8]) {
        let replies = terminal.receive(bytes)
        if !replies.isEmpty {
            pseudoTerminal?.write(replies)
        }
    }
}

extension TerminalSession.Termination {
    fileprivate init(_ termination: PseudoTerminal.Termination) {
        switch termination {
        case .exit(let status):
            self = .exit(status)
        case .uncaughtSignal(let signal):
            self = .uncaughtSignal(signal)
        }
    }
}
