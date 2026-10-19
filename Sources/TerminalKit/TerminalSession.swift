import Foundation
import Observation
import TerminalCore

@MainActor
@Observable
public final class TerminalSession {
    public enum State: Hashable, Sendable {
        case idle
        case running
        case exited(Termination)
    }

    public enum Termination: Hashable, Sendable {
        case exit(Int32)
        case uncaughtSignal(Int32)
    }

    private let configuration: Configuration
    public private(set) var state = State.idle
    public private(set) var title = ""
    public private(set) var bellCount = 0
    public private(set) var commands: [Command] = []
    public private(set) var currentDirectory: URL?
    private(set) var revealedCommandID: Int?
    private(set) var revealCount = 0
    @ObservationIgnored var handledRevealCount = 0

    private(set) var liveTerminal = Terminal(columns: 80, rows: 24) {
        didSet {
            revision += 1
        }
    }
    @ObservationIgnored var synchronizedOutputTimeout = Duration.seconds(1)
    @ObservationIgnored var synchronizedOutputClock: any Clock<Duration> = ContinuousClock()
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private(set) var widthChangeCount = 0
    @ObservationIgnored weak var sizingView: TerminalContentView? {
        didSet {
            sizingViewChangeCount += 1
        }
    }
    private(set) var sizingViewChangeCount = 0

    @ObservationIgnored private var pseudoTerminal: PseudoTerminal?
    @ObservationIgnored private var commandEventContinuations: [Int: AsyncStream<CommandEvent>.Continuation] = [:]
    @ObservationIgnored private var nextCommandEventID = 0
    @ObservationIgnored private var synchronizedOutputTimer: Task<Void, Never>?
    @ObservationIgnored private var timedSynchronizedOutputCount = 0

    var terminal: Terminal {
        liveTerminal.displayed
    }

    public init(configuration: Configuration = .loginShell) {
        self.configuration = configuration
    }

    public init(configuration: Configuration = .loginShell, restoring state: RestorationState) {
        var configuration = configuration
        var isDirectory: ObjCBool = false
        if let directory = state.terminal.currentDirectory?.path(percentEncoded: false),
            FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue,
            FileManager.default.isExecutableFile(atPath: directory)
        {
            configuration.currentDirectoryURL = URL(filePath: directory)
        }
        self.configuration = configuration
        liveTerminal = Terminal(restoring: state.terminal)
        currentDirectory = liveTerminal.currentDirectory
        let firstID = liveTerminal.removedCommandCount
        let savedCommands = Dictionary(state.commands.map { ($0.id, $0) }) { $1 }
        commands = liveTerminal.commands.enumerated()
            .map { index, command in
                let saved = savedCommands[firstID + index]
                return Command(
                    id: firstID + index,
                    text: command.text,
                    directory: command.directory,
                    exitStatus: command.exitStatus,
                    startDate: saved?.startDate ?? state.date,
                    endDate: saved?.endDate ?? state.date
                )
            }
    }

    public var restorationState: RestorationState {
        RestorationState(terminal: liveTerminal.restoration, commands: commands, date: Date())
    }

    public func start() throws {
        guard state == .idle else {
            return
        }
        var configuration = configuration
        let nonce = UUID().uuidString
        if configuration.usesShellIntegration, let directory = try? ShellIntegration.install(),
            let integrated = configuration.integratingShell(scriptsIn: directory, nonce: nonce)
        {
            configuration = integrated
            liveTerminal.shellIntegrationNonce = nonce
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

    public func reveal(_ command: Command) {
        revealedCommandID = command.id
        revealCount += 1
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

    public var hasForegroundProcess: Bool {
        guard let pseudoTerminal, let group = pseudoTerminal.foregroundProcessGroup else {
            return false
        }
        return group != pseudoTerminal.processIdentifier
    }

    public func terminate() {
        pseudoTerminal?.hangUp()
    }

    public func send(_ text: String) {
        send(Array(text.utf8))
    }

    public func paste(_ text: String) {
        let lines = text.replacing("\r\n", with: "\r").replacing("\n", with: "\r")
        guard liveTerminal.usesBracketedPaste else {
            send(lines)
            return
        }
        send("\u{1B}[200~\(lines.replacing("\u{1B}", with: ""))\u{1B}[201~")
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
            send(.finished(commands[last]))
        }
        for continuation in commandEventContinuations.values {
            continuation.finish()
        }
        commandEventContinuations.removeAll()
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
            synchronizedOutputTimer = Task { [weak self, synchronizedOutputTimeout, synchronizedOutputClock] in
                try? await synchronizedOutputClock.sleep(for: synchronizedOutputTimeout)
                guard let self, !Task.isCancelled, liveTerminal.isSynchronizingOutput else {
                    return
                }
                liveTerminal.endSynchronizedOutput()
            }
        }
    }
}

extension TerminalSession {
    public struct RestorationState: Codable, Equatable, Sendable {
        let terminal: Terminal.Restoration
        let commands: [Command]
        let date: Date
    }

    public struct Command: Identifiable, Codable, Hashable, Sendable {
        public let id: Int
        public let text: String?
        public let directory: URL?
        public internal(set) var exitStatus: Int32?
        public let startDate: Date
        public internal(set) var endDate: Date?

        public init(
            id: Int,
            text: String?,
            directory: URL? = nil,
            exitStatus: Int32? = nil,
            startDate: Date,
            endDate: Date? = nil
        ) {
            self.id = id
            self.text = text
            self.directory = directory
            self.exitStatus = exitStatus
            self.startDate = startDate
            self.endDate = endDate
        }
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
                    send(.finished(commands[commands.count - 1]))
                }
            } else {
                var started = Command(
                    id: id,
                    text: command.text,
                    directory: command.directory,
                    exitStatus: nil,
                    startDate: date,
                    endDate: nil
                )
                send(.started(started))
                if command.isFinished {
                    started.exitStatus = command.exitStatus
                    started.endDate = date
                    send(.finished(started))
                }
                commands.append(started)
            }
        }
    }
}

extension TerminalSession {
    public enum CommandEvent: Hashable, Sendable {
        case started(Command)
        case finished(Command)
    }

    public func commandEvents() -> AsyncStream<CommandEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CommandEvent.self)
        if case .exited = state {
            continuation.finish()
            return stream
        }
        let id = nextCommandEventID
        nextCommandEventID += 1
        commandEventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.commandEventContinuations[id] = nil
            }
        }
        return stream
    }

    private func send(_ event: CommandEvent) {
        for continuation in commandEventContinuations.values {
            continuation.yield(event)
        }
    }
}

extension TerminalSession: Identifiable, Hashable {
    public nonisolated static func == (lhs: TerminalSession, rhs: TerminalSession) -> Bool {
        lhs === rhs
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
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
