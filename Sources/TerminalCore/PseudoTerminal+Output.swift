import Dispatch
import Synchronization

extension PseudoTerminal {
    package struct Output: AsyncSequence, Sendable {
        let wakeUps: AsyncStream<Void>
        let buffer: OutputBuffer

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(wakeUps: wakeUps.makeAsyncIterator(), buffer: buffer)
        }

        package struct AsyncIterator: AsyncIteratorProtocol {
            var wakeUps: AsyncStream<Void>.Iterator
            let buffer: OutputBuffer

            package mutating func next(isolation actor: isolated (any Actor)? = #isolation) async -> [UInt8]? {
                while await wakeUps.next(isolation: actor) != nil {
                    let bytes = buffer.take()
                    if !bytes.isEmpty {
                        return bytes
                    }
                }
                return nil
            }

            package mutating func next() async -> [UInt8]? {
                await next(isolation: nil)
            }
        }
    }

    final class OutputBuffer: Sendable {
        private struct State {
            var bytes: [UInt8] = []
            var isSuspended = false
            var isCancelled = false
        }

        private static let capacity = 65_536

        private let source: any DispatchSourceRead
        private let wakeUp: AsyncStream<Void>.Continuation
        private let state = Mutex(State())

        init(source: any DispatchSourceRead, wakeUp: AsyncStream<Void>.Continuation) {
            self.source = source
            self.wakeUp = wakeUp
        }

        func append(_ bytes: [UInt8]) {
            state.withLock { state in
                if state.bytes.isEmpty {
                    wakeUp.yield()
                }
                state.bytes += bytes
                if state.bytes.count >= Self.capacity, !state.isSuspended, !state.isCancelled {
                    state.isSuspended = true
                    source.suspend()
                }
            }
        }

        func take() -> [UInt8] {
            state.withLock { state in
                if state.isSuspended, !state.isCancelled {
                    state.isSuspended = false
                    source.resume()
                }
                var bytes: [UInt8] = []
                swap(&bytes, &state.bytes)
                return bytes
            }
        }

        func cancel() {
            state.withLock { state in
                guard !state.isCancelled else {
                    return
                }
                state.isCancelled = true
                if state.isSuspended {
                    state.isSuspended = false
                    source.resume()
                }
                source.cancel()
            }
        }
    }
}
