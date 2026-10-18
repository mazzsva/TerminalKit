import Foundation
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
    public private(set) var title = ""
    public private(set) var bellCount = 0
    public private(set) var commands: [Command] = []
    public private(set) var currentDirectory: URL?

    private(set) var liveTerminal = Terminal(columns: 80, rows: 24) {
        didSet {
            revision += 1
        }
    }
    @ObservationIgnored var synchronizedOutputTimeout = Duration.seconds(1)
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private(set) var widthChangeCount = 0

    @ObservationIgnored private var pseudoTerminal: PseudoTerminal?
    @ObservationIgnored private var synchronizedOutputTimer: Task<Void, Never>?
    @ObservationIgnored private var timedSynchronizedOutputCount = 0

    var terminal: Terminal {
        liveTerminal.displayed
    }

    public init(configuration: Configuration = .loginShell) {
        self.configuration = configuration
    }

    public func start() throws {
        guard state == .idle else {
            return
        }
        var configuration = configuration
        if configuration.usesShellIntegration, let directory = try? ShellIntegration.install() {
            configuration = configuration.integratingShell(scriptsIn: directory)
        }
        let pseudoTerminal = try PseudoTerminal(
            executableURL: configuration.executableURL,
            arguments: configuration.arguments,
            environment: configuration.environment,
            currentDirectoryURL: configuration.currentDirectoryURL,
            columns: liveTerminal.columns,
            rows: liveTerminal.rows
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
        guard columns != liveTerminal.columns || rows != liveTerminal.rows else {
            return
        }
        if columns != liveTerminal.columns {
            widthChangeCount += 1
        }
        liveTerminal.resize(columns: columns, rows: rows)
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
        if let last = commands.indices.last, commands[last].endDate == nil {
            commands[last].endDate = Date()
        }
        if liveTerminal.isSynchronizingOutput {
            liveTerminal.endSynchronizedOutput()
        }
    }

    private func receive(_ bytes: [UInt8]) {
        let replies = liveTerminal.receive(bytes)
        title = liveTerminal.title
        if bellCount != liveTerminal.bellCount {
            bellCount = liveTerminal.bellCount
        }
        if currentDirectory != liveTerminal.currentDirectory {
            currentDirectory = liveTerminal.currentDirectory
        }
        updateCommands()
        if !replies.isEmpty {
            pseudoTerminal?.write(replies)
        }
        let count = liveTerminal.synchronizedOutputCount
        if liveTerminal.isSynchronizingOutput, count != timedSynchronizedOutputCount {
            timedSynchronizedOutputCount = count
            synchronizedOutputTimer?.cancel()
            synchronizedOutputTimer = Task { [weak self, synchronizedOutputTimeout] in
                try? await Task.sleep(for: synchronizedOutputTimeout)
                guard let self, !Task.isCancelled, liveTerminal.isSynchronizingOutput else {
                    return
                }
                liveTerminal.endSynchronizedOutput()
            }
        }
    }
}

extension TerminalSession {
    public struct Command: Identifiable, Equatable, Sendable {
        public let id: Int
        public let text: String?
        public let directory: URL?
        public internal(set) var exitStatus: Int32?
        public let startDate: Date
        public internal(set) var endDate: Date?
    }

    private func updateCommands() {
        let firstID = liveTerminal.removedCommandCount
        if let id = commands.first?.id, id < firstID {
            commands.removeFirst(min(firstID - id, commands.count))
        }
        let date = Date()
        let start = commands.last.map { $0.endDate == nil ? $0.id : $0.id + 1 } ?? firstID
        for id in max(start, firstID) ..< firstID + liveTerminal.commands.count {
            let command = liveTerminal.commands[id - firstID]
            if id == commands.last?.id {
                if command.isFinished {
                    commands[commands.count - 1].exitStatus = command.exitStatus
                    commands[commands.count - 1].endDate = date
                }
            } else {
                commands.append(
                    Command(
                        id: id,
                        text: command.text,
                        directory: command.directory,
                        exitStatus: command.exitStatus,
                        startDate: date,
                        endDate: command.isFinished ? date : nil
                    )
                )
            }
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
