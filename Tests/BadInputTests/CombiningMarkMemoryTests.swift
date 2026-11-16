import Foundation
import Testing

@testable import TerminalCore

let processMemory = ProcessMemory()

@Suite(.serialized, .timeLimit(.minutes(10)))
struct CombiningMarkMemoryTests {
    static let limit = 64 * 1_048_576

    @Test func limitsTheMemoryOfLongChainsOfMarks() async {
        await processMemory.startMeasurement()
        var terminal = Terminal(columns: 80, rows: 24)
        var random = SplitMix64(state: 0x5EED)
        let before = processMemory.footprint()
        receive(megabytes: 1, marksPerCell: 500, into: &terminal, using: &random)
        #expect(processMemory.footprint() - before < Self.limit)
        await processMemory.leave()
    }

    @Test func freesTheMemoryOfManyChainsOfMarksAfterAReset() async {
        await processMemory.startMeasurement()
        let before = processMemory.footprint()
        var terminal = Terminal(columns: 80, rows: 24)
        var random = SplitMix64(state: 0x5EED)
        receive(megabytes: 20, marksPerCell: 4, into: &terminal, using: &random)
        _ = terminal.receive(Array("\u{1B}[3J\u{1B}c".utf8))
        #expect(processMemory.footprint() - before < Self.limit)
        await processMemory.leave()
    }

    private func receive(
        megabytes: Int, marksPerCell: Int, into terminal: inout Terminal, using random: inout SplitMix64
    ) {
        var sent = 0
        while sent < megabytes * 1_048_576 {
            var bytes: [UInt8] = []
            for _ in 0 ..< 2_000 / marksPerCell {
                bytes.append(0x61)
                for _ in 0 ..< marksPerCell {
                    let mark = 0x300 + UInt32.random(in: 0 ..< 112, using: &random)
                    bytes += [UInt8(0xC0 | mark >> 6), UInt8(0x80 | mark & 0x3F)]
                }
            }
            sent += bytes.count
            _ = terminal.receive(bytes)
        }
    }
}

actor ProcessMemory {
    private var sharedCount = 0
    private var isMeasuring = false
    private var waitingCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func startSharing() async {
        while isMeasuring || waitingCount > 0 {
            await withCheckedContinuation { waiters.append($0) }
        }
        sharedCount += 1
    }

    func startMeasurement() async {
        waitingCount += 1
        while isMeasuring || sharedCount > 0 {
            await withCheckedContinuation { waiters.append($0) }
        }
        waitingCount -= 1
        isMeasuring = true
    }

    func leave() {
        if isMeasuring {
            isMeasuring = false
        } else {
            sharedCount -= 1
        }
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    nonisolated func footprint() -> Int {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &information) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return Int(information.phys_footprint)
    }
}
