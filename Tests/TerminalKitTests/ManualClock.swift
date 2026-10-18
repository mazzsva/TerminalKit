import Synchronization

final class ManualClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [(deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = []
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let isDue = state.withLock { state in
                guard deadline > state.now else {
                    return true
                }
                state.sleepers.append((deadline, continuation))
                return false
            }
            if isDue {
                continuation.resume()
            }
        }
    }

    func waitForSleepers(_ count: Int) async throws {
        while state.withLock({ $0.sleepers.count }) < count {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}
