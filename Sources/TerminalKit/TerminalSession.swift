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

    public struct ProgramStatus: Hashable, Sendable {
        public enum State: Hashable, Sendable {
            case idle
            case working
            case done
            case blocked
        }

        public let state: State
        public let application: String?
        public let kind: String?
        public let message: String?
    }

    private let configuration: Configuration
    public private(set) var state = State.idle
    public private(set) var title = ""
    public private(set) var bellCount = 0
    public private(set) var currentDirectoryURL: URL?
    public private(set) var programStatus: ProgramStatus?

    var liveTerminal = Terminal(columns: 80, rows: 24) {
        didSet {
            revision += 1
            terminalDidChange?()
        }
    }
    @ObservationIgnored var synchronizedOutputClock: any Clock<Duration> = ContinuousClock()
    @ObservationIgnored var terminalDidChange: (() -> Void)?
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private(set) var resizeCount = 0
    @ObservationIgnored weak var sizingView: TerminalContentView?
    @ObservationIgnored var isShown = false
    @ObservationIgnored private var isSized = false
    @ObservationIgnored private var cellSize = CGSize(width: 7, height: 15)
    @ObservationIgnored private var waitingInput: [UInt8]?

    @ObservationIgnored private(set) var pseudoTerminal: PseudoTerminal?
    @ObservationIgnored private var synchronizedOutputTimer: Task<Void, Never>?
    @ObservationIgnored private var timedSynchronizedOutputCount = 0
    @ObservationIgnored var outputActivityClock: any Clock<Duration> = ContinuousClock()
    @ObservationIgnored private(set) var outputActivity: (any NSObjectProtocol)?
    @ObservationIgnored private var outputActivityTimer: Task<Void, Never>?

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
            rows: liveTerminal.rows,
            pixelWidth: pixelWidth(columns: liveTerminal.columns),
            pixelHeight: pixelHeight(rows: liveTerminal.rows)
        )
        self.pseudoTerminal = pseudoTerminal
        if let waitingInput {
            pseudoTerminal.write(waitingInput)
            self.waitingInput = nil
        }
        state = .running

        let output = pseudoTerminal.output
        Task { [weak self] in
            let clock = ContinuousClock()
            for await bytes in output {
                let deadline = clock.now + .milliseconds(16)
                self?.receive(bytes)
                while clock.now < deadline {
                    let bytes = output.takeAvailable()
                    guard !bytes.isEmpty else {
                        break
                    }
                    self?.receive(bytes)
                }
            }
            self?.finish()
        }
    }

    func resize(columns: Int, rows: Int, cellSize: CGSize = CGSize(width: 7, height: 15)) {
        isSized = true
        defer { startIfWaiting() }
        guard columns != liveTerminal.columns || rows != liveTerminal.rows || cellSize != self.cellSize else {
            return
        }
        self.cellSize = cellSize
        if columns != liveTerminal.columns || rows != liveTerminal.rows {
            resizeCount += 1
            liveTerminal.resize(columns: columns, rows: rows)
        }
        pseudoTerminal?
            .resize(
                columns: columns,
                rows: rows,
                pixelWidth: pixelWidth(columns: columns),
                pixelHeight: pixelHeight(rows: rows)
            )
    }

    private func pixelWidth(columns: Int) -> Int {
        Int(CGFloat(columns) * cellSize.width)
    }

    private func pixelHeight(rows: Int) -> Int {
        Int(CGFloat(rows) * cellSize.height)
    }

    public var hasForegroundProcess: Bool {
        guard let pseudoTerminal, let group = pseudoTerminal.foregroundProcessGroup else {
            return false
        }
        guard configuration.isLoginShell else {
            return true
        }
        guard group != pseudoTerminal.processIdentifier else {
            return false
        }
        var information = proc_bsdshortinfo()
        let size = proc_pidinfo(
            group, PROC_PIDT_SHORTBSDINFO, 0, &information, Int32(MemoryLayout<proc_bsdshortinfo>.size))
        return size <= 0 || pid_t(information.pbsi_ppid) != pseudoTerminal.processIdentifier
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

    static let pasteEnd = "\u{1B}[201~"

    static func containsPasteEnd(_ text: String) -> Bool {
        text.utf8.firstRange(of: pasteEnd.utf8) != nil
    }

    public func paste(_ text: String) {
        if let bytes = Self.pastedBytes(text, isBracketed: liveTerminal.usesBracketedPaste) {
            send(bytes)
        }
    }

    static func pastedBytes(_ text: String, isBracketed: Bool) -> [UInt8]? {
        let lines = text.replacing("\r\n", with: "\r").replacing("\n", with: "\r")
        guard isBracketed else {
            return Array(lines.utf8)
        }
        guard !containsPasteEnd(lines) else {
            return nil
        }
        return Array("\u{1B}[200~\(lines)\(pasteEnd)".utf8)
    }

    func clearToStart() {
        liveTerminal.clearToStart()
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
        programStatus = nil
        state = .exited(Termination(termination))
        pseudoTerminal = nil
        if liveTerminal.isSynchronizingOutput {
            liveTerminal.endSynchronizedOutput()
        }
        endOutputActivity()
    }

    private func beginOutputActivity() {
        let activity =
            outputActivity
            ?? ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Terminal output")
        outputActivity = activity
        outputActivityTimer?.cancel()
        outputActivityTimer = Task { [weak self, outputActivityClock] in
            try? await outputActivityClock.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                ProcessInfo.processInfo.endActivity(activity)
                return
            }
            endOutputActivity()
        }
    }

    private func endOutputActivity() {
        outputActivityTimer?.cancel()
        outputActivityTimer = nil
        if let outputActivity {
            ProcessInfo.processInfo.endActivity(outputActivity)
        }
        outputActivity = nil
    }

    func receive(_ bytes: [UInt8]) {
        if bytes.count >= PseudoTerminal.Output.capacity {
            beginOutputActivity()
        }
        if let view = sizingView, view.reportedColors != liveTerminal.defaultColors {
            liveTerminal.defaultColors = view.reportedColors
        }
        let replies = liveTerminal.receive(bytes)
        title = liveTerminal.title
        if bellCount != liveTerminal.bellCount {
            bellCount = liveTerminal.bellCount
        }
        if currentDirectoryURL != liveTerminal.currentDirectory {
            currentDirectoryURL = liveTerminal.currentDirectory
        }
        let status = liveTerminal.programStatus.map(ProgramStatus.init)
        if programStatus != status {
            programStatus = status
        }
        if !replies.isEmpty {
            pseudoTerminal?.write(replies, isReply: true)
        }
        let count = liveTerminal.synchronizedOutputCount
        if liveTerminal.isSynchronizingOutput, count != timedSynchronizedOutputCount {
            timedSynchronizedOutputCount = count
            synchronizedOutputTimer?.cancel()
            synchronizedOutputTimer = Task { [weak self, synchronizedOutputClock] in
                try? await synchronizedOutputClock.sleep(for: .seconds(1))
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

extension TerminalSession.ProgramStatus {
    fileprivate init(_ status: Terminal.ProgramStatus) {
        switch status.state {
        case .idle:
            state = .idle
        case .working:
            state = .working
        case .done:
            state = .done
        case .blocked:
            state = .blocked
        }
        application = status.application
        kind = status.kind
        message = status.message
    }
}
