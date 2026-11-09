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
    public private(set) var currentDirectoryURL: URL?

    private(set) var terminal = Terminal(columns: 80, rows: 24) {
        didSet {
            revision += 1
        }
    }
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private(set) var resizeCount = 0
    @ObservationIgnored weak var sizingView: TerminalContentView?
    @ObservationIgnored var isShown = false
    @ObservationIgnored private var isSized = false
    @ObservationIgnored private var cellSize = CGSize(width: 7, height: 15)
    @ObservationIgnored private var waitingInput: [UInt8]?
    @ObservationIgnored var showsProcessCompletion = true

    @ObservationIgnored private(set) var pseudoTerminal: PseudoTerminal?

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
            columns: terminal.columns,
            rows: terminal.rows,
            pixelWidth: pixelWidth(columns: terminal.columns),
            pixelHeight: pixelHeight(rows: terminal.rows)
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

    func resize(columns: Int, rows: Int, cellSize: CGSize = CGSize(width: 7, height: 15)) {
        isSized = true
        defer { startIfWaiting() }
        guard columns != terminal.columns || rows != terminal.rows || cellSize != self.cellSize else {
            return
        }
        self.cellSize = cellSize
        if columns != terminal.columns || rows != terminal.rows {
            resizeCount += 1
            terminal.resize(columns: columns, rows: rows)
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
        let lines = text.replacing("\r\n", with: "\r").replacing("\n", with: "\r")
        guard terminal.usesBracketedPaste else {
            send(lines)
            return
        }
        guard !Self.containsPasteEnd(lines) else {
            return
        }
        send("\u{1B}[200~\(lines)\(Self.pasteEnd)")
    }

    func clearToStart() {
        terminal.clearToStart()
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
        if showsProcessCompletion {
            terminal.completeProcess()
        }
        state = .exited(Termination(termination))
        pseudoTerminal = nil
    }

    private func receive(_ bytes: [UInt8]) {
        if let view = sizingView, view.reportedColors != terminal.defaultColors {
            terminal.defaultColors = view.reportedColors
        }
        if let report = sizingView?.windowReport {
            if report != terminal.windowReport {
                terminal.windowReport = report
            }
        } else if terminal.windowReport.isVisible {
            terminal.windowReport.isVisible = false
        }
        let replies = terminal.receive(bytes)
        title = terminal.title
        if bellCount != terminal.bellCount {
            bellCount = terminal.bellCount
        }
        if currentDirectoryURL != terminal.currentDirectory {
            currentDirectoryURL = terminal.currentDirectory
        }
        if !replies.isEmpty {
            pseudoTerminal?.write(replies, isReply: true)
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
