import CTerminalCore
import Darwin
import Foundation
import Synchronization

package final class PseudoTerminal: Sendable {
    package enum Termination: Equatable, Sendable {
        case exit(Int32)
        case uncaughtSignal(Int32)
    }

    private static let readSize = 65_536
    private static let maximumOpenRetries = 10
    private static let redriveOpenError: Int32 = -6

    package let processIdentifier: pid_t
    package let output: Output

    private let fileDescriptor: Int32
    private let wakeUp: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "PseudoTerminal")
    private let readSource: any DispatchSourceRead
    private let buffer: OutputBuffer
    private let input = Mutex(Input())
    private let finalTermination = Mutex<Termination?>(nil)

    package var termination: Termination? {
        finalTermination.withLock { $0 }
    }

    private struct Input {
        var bytes: [UInt8] = []
        var offset = 0
        var writeSource: (any DispatchSourceWrite)?
    }

    package init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String],
        currentDirectoryURL: URL? = nil,
        columns: Int,
        rows: Int
    ) throws(POSIXError) {
        let (primary, secondary) = try Self.openTerminal(columns: columns, rows: rows)
        do {
            processIdentifier = try Self.spawn(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                currentDirectoryURL: currentDirectoryURL,
                terminal: secondary
            )
        } catch {
            close(primary)
            close(secondary)
            throw error
        }
        fileDescriptor = primary
        let wakeUps: AsyncStream<Void>
        (wakeUps, wakeUp) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        readSource = DispatchSource.makeReadSource(fileDescriptor: primary, queue: queue)
        buffer = OutputBuffer(source: readSource, wakeUp: wakeUp)
        output = Output(wakeUps: wakeUps, buffer: buffer)
        readSource.setEventHandler { [weak self] in
            self?.readOutput()
        }
        readSource.setCancelHandler {
            close(primary)
        }
        readSource.activate()
        monitorExit(secondary: secondary)
    }

    deinit {
        cancelSources()
        wakeUp.finish()
    }

    package func write(_ bytes: [UInt8]) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            input.withLock { $0.bytes += bytes }
            writeInput()
        }
    }

    package func resize(columns: Int, rows: Int) {
        queue.async { [weak self] in
            guard let self, !readSource.isCancelled else {
                return
            }
            var size = winsize(columns: columns, rows: rows)
            _ = ioctl(fileDescriptor, TIOCSWINSZ, &size)
        }
    }

    private func writeInput() {
        input.withLock { input in
            while input.offset < input.bytes.count, !readSource.isCancelled {
                var error: Int32 = 0
                let count = input.bytes[input.offset...]
                    .withUnsafeBytes { buffer in
                        let count = Darwin.write(fileDescriptor, buffer.baseAddress, buffer.count)
                        error = errno
                        return count
                    }
                if count > 0 {
                    input.offset += count
                } else if count < 0 && error == EAGAIN {
                    if input.offset > input.bytes.count / 2 {
                        input.bytes.removeFirst(input.offset)
                        input.offset = 0
                    }
                    if input.writeSource == nil {
                        let writeSource = DispatchSource.makeWriteSource(fileDescriptor: fileDescriptor, queue: queue)
                        writeSource.setEventHandler { [weak self] in
                            self?.writeInput()
                        }
                        writeSource.activate()
                        input.writeSource = writeSource
                    }
                    return
                } else if count == 0 || error != EINTR {
                    break
                }
            }
            input.bytes.removeAll()
            input.offset = 0
            input.writeSource?.cancel()
            input.writeSource = nil
        }
    }

    private func monitorExit(secondary: Int32) {
        let processIdentifier = processIdentifier
        Thread { [weak self] in
            var status: Int32 = 0
            while waitpid(processIdentifier, &status, 0) == -1 && errno == EINTR {}
            let termination = Termination(status: status)
            close(secondary)
            guard let self else {
                return
            }
            queue.async {
                self.finish(termination)
            }
        }
        .start()
    }

    @discardableResult
    private func readOutput() -> Bool {
        guard !readSource.isCancelled else {
            return false
        }
        var result = 0
        var error: Int32 = 0
        let bytes = [UInt8](unsafeUninitializedCapacity: Self.readSize) { buffer, count in
            result = read(fileDescriptor, buffer.baseAddress, buffer.count)
            error = errno
            count = max(result, 0)
        }
        if result > 0 {
            buffer.append(bytes)
            return true
        }
        if result < 0 && error == EINTR {
            return true
        }
        if result == 0 || error != EAGAIN {
            cancelSources()
        }
        return false
    }

    private func cancelSources() {
        input.withLock { input in
            input.writeSource?.cancel()
            input.writeSource = nil
        }
        buffer.cancel()
    }

    private func finish(_ termination: Termination) {
        finalTermination.withLock { $0 = termination }
        while readOutput() {}
        cancelSources()
        wakeUp.finish()
    }

    package static func openTerminal(columns: Int, rows: Int) throws(POSIXError) -> (primary: Int32, secondary: Int32) {
        var primary = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC)
        var retries = 0
        while primary == -1, errno == ENXIO || errno == redriveOpenError, retries < maximumOpenRetries {
            retries += 1
            primary = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC)
        }
        guard primary != -1 else {
            throw POSIXError(errno)
        }
        var name = [CChar](repeating: 0, count: 128)
        guard grantpt(primary) == 0, unlockpt(primary) == 0, ptsname_r(primary, &name, name.count) == 0 else {
            let error = errno
            close(primary)
            throw POSIXError(error)
        }
        let secondary = open(name, O_RDWR | O_NOCTTY | O_CLOEXEC)
        guard secondary != -1 else {
            let error = errno
            close(primary)
            throw POSIXError(error)
        }
        var size = winsize(columns: columns, rows: rows)
        _ = ioctl(secondary, TIOCSWINSZ, &size)
        _ = fcntl(primary, F_SETFL, fcntl(primary, F_GETFL) | O_NONBLOCK)
        return (primary, secondary)
    }

    private static func spawn(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        terminal: Int32
    ) throws(POSIXError) -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        for standardStream in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_adddup2(&fileActions, terminal, standardStream)
        }
        if let currentDirectoryURL {
            posix_spawn_file_actions_addchdir(&fileActions, currentDirectoryURL.path(percentEncoded: false))
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var signals = sigset_t()
        sigfillset(&signals)
        posix_spawnattr_setsigdefault(&attributes, &signals)
        sigemptyset(&signals)
        posix_spawnattr_setsigmask(&attributes, &signals)
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETEXEC | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )

        let path = executableURL.path(percentEncoded: false)
        let argumentPointers = ([path] + arguments).map { strdup($0) } + [nil]
        let environmentPointers = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argumentPointers + environmentPointers {
                free(pointer)
            }
        }

        var processIdentifier: pid_t = 0
        let result = spawn_in_terminal(
            &processIdentifier,
            terminal,
            path,
            &fileActions,
            &attributes,
            argumentPointers,
            environmentPointers
        )
        guard result == 0 else {
            throw POSIXError(result)
        }
        return processIdentifier
    }
}

extension PseudoTerminal.Termination {
    fileprivate init(status: Int32) {
        let signal = status & 0x7F
        self = signal == 0 ? .exit(status >> 8 & 0xFF) : .uncaughtSignal(signal)
    }
}

extension winsize {
    fileprivate init(columns: Int, rows: Int) {
        self.init(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
    }
}

extension POSIXError {
    fileprivate init(_ code: Int32) {
        self.init(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
