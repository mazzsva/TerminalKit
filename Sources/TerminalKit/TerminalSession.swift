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

    public let configuration: Configuration
    public private(set) var state = State.idle

    public var title: String {
        terminal.title
    }

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

        let events = pseudoTerminal.events
        Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: PseudoTerminal.Event) {
        switch event {
        case .output(let bytes):
            terminal.receive(bytes)
        case .exit(let termination):
            state = .exited(Termination(termination))
            pseudoTerminal = nil
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
