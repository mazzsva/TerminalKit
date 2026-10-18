import Dispatch
import Synchronization

extension PseudoTerminal {
    package struct Output: AsyncSequence, Sendable {
        let stream: AsyncStream<[UInt8]>
        let flowControl: FlowControl

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(iterator: stream.makeAsyncIterator(), flowControl: flowControl)
        }

        package struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: AsyncStream<[UInt8]>.Iterator
            let flowControl: FlowControl

            package mutating func next(isolation actor: isolated (any Actor)? = #isolation) async -> [UInt8]? {
                let bytes = await iterator.next(isolation: actor)
                if bytes != nil {
                    flowControl.didRead()
                }
                return bytes
            }

            package mutating func next() async -> [UInt8]? {
                await next(isolation: nil)
            }
        }
    }

    final class FlowControl: Sendable {
        private struct State {
            var unreadEvents = 0
            var isSuspended = false
            var isCancelled = false
        }

        private static let maximumUnreadEvents = 4

        private let source: any DispatchSourceRead
        private let state = Mutex(State())

        init(source: any DispatchSourceRead) {
            self.source = source
        }

        func didYield() {
            state.withLock { state in
                state.unreadEvents += 1
                if state.unreadEvents >= Self.maximumUnreadEvents, !state.isSuspended, !state.isCancelled {
                    state.isSuspended = true
                    source.suspend()
                }
            }
        }

        func didRead() {
            state.withLock { state in
                state.unreadEvents -= 1
                if state.unreadEvents < Self.maximumUnreadEvents, state.isSuspended, !state.isCancelled {
                    state.isSuspended = false
                    source.resume()
                }
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
