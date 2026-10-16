import Darwin
import Foundation

package final class PseudoTerminal: Sendable {
    package enum Event: Equatable, Sendable {
        case exit(Termination)
    }

    package enum Termination: Equatable, Sendable {
        case exit(Int32)
        case uncaughtSignal(Int32)
    }

    package let processIdentifier: pid_t
    package let events: AsyncStream<Event>

    private let fileDescriptor: Int32
    private let continuation: AsyncStream<Event>.Continuation
    private let queue = DispatchQueue(label: "PseudoTerminal")

    package init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String],
        columns: Int,
        rows: Int
    ) throws(POSIXError) {
        var size = winsize(
            ws_row: UInt16(clamping: rows),
            ws_col: UInt16(clamping: columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        var primary: Int32 = -1
        var secondary: Int32 = -1
        guard openpty(&primary, &secondary, nil, nil, &size) == 0 else {
            throw POSIXError(errno)
        }
        defer { close(secondary) }
        _ = fcntl(primary, F_SETFD, FD_CLOEXEC)

        do {
            processIdentifier = try Self.spawn(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                terminal: secondary
            )
        } catch {
            close(primary)
            throw error
        }
        fileDescriptor = primary
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        monitorExit()
    }

    deinit {
        close(fileDescriptor)
        continuation.finish()
    }

    private func monitorExit() {
        let processIdentifier = processIdentifier
        let source = DispatchSource.makeProcessSource(identifier: processIdentifier, eventMask: .exit, queue: queue)
        let reap: @Sendable () -> Void = { [weak self] in
            var status: Int32 = 0
            guard waitpid(processIdentifier, &status, WNOHANG) == processIdentifier else {
                return
            }
            source.cancel()
            self?.finish(Termination(status: status))
        }
        source.setEventHandler(handler: reap)
        source.activate()
        queue.async(execute: reap)
    }

    private func finish(_ termination: Termination) {
        continuation.yield(.exit(termination))
        continuation.finish()
    }

    private static func spawn(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        terminal: Int32
    ) throws(POSIXError) -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        for standardStream in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_adddup2(&fileActions, terminal, standardStream)
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
            Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
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
        let result = posix_spawn(
            &processIdentifier, path, &fileActions, &attributes, argumentPointers, environmentPointers)
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

extension POSIXError {
    fileprivate init(_ code: Int32) {
        self.init(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
