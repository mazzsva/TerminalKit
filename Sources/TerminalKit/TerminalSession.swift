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
    public private(set) var currentDirectory: URL?

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
    @ObservationIgnored var isShown = false
    @ObservationIgnored private var isSized = false
    @ObservationIgnored private var waitingInput: [UInt8]?

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
        guard isSized || !isShown else {
            waitingInput = waitingInput ?? []
            return
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
        if let waitingInput {
            pseudoTerminal.write(waitingInput)
            self.waitingInput = nil
        }
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
        isSized = true
        defer { startIfWaiting() }
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
        return !configuration.isLoginShell || group != pseudoTerminal.processIdentifier
    }

    public func terminate() {
        if waitingInput != nil {
            waitingInput = nil
            state = .exited(.uncaughtSignal(SIGHUP))
        }
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
        waitingInput? += bytes
        pseudoTerminal?.write(bytes)
    }

    private func startIfWaiting() {
        guard waitingInput != nil else {
            return
        }
        do {
            try start()
        } catch {
            waitingInput = nil
            state = .exited(.exit(127))
        }
    }

    private func finish() {
        guard let termination = pseudoTerminal?.termination else {
            return
        }
        state = .exited(Termination(termination))
        pseudoTerminal = nil
        if liveTerminal.isSynchronizingOutput {
            liveTerminal.endSynchronizedOutput()
        }
    }

    private func receive(_ bytes: [UInt8]) {
        if let colors = sizingView?.reportedColors, colors != liveTerminal.reportedColors {
            liveTerminal.reportedColors = colors
        }
        let replies = liveTerminal.receive(bytes)
        title = liveTerminal.title
        if bellCount != liveTerminal.bellCount {
            bellCount = liveTerminal.bellCount
        }
        if currentDirectory != liveTerminal.currentDirectory {
            currentDirectory = liveTerminal.currentDirectory
        }
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

extension TerminalSession: nonisolated Identifiable, nonisolated Hashable {
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
