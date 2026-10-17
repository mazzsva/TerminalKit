import Dispatch
import Synchronization

extension PseudoTerminal {
    package struct Events: AsyncSequence, Sendable {
        let stream: AsyncStream<Event>
        let flowControl: FlowControl

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(iterator: stream.makeAsyncIterator(), flowControl: flowControl)
        }

        package struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: AsyncStream<Event>.Iterator
            let flowControl: FlowControl

            package mutating func next(isolation actor: isolated (any Actor)? = #isolation) async -> Event? {
                let event = await iterator.next(isolation: actor)
                if event != nil {
                    flowControl.didRead()
                }
                return event
            }

            package mutating func next() async -> Event? {
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
