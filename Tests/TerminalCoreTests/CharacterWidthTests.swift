import Foundation
import Testing

@testable import TerminalCore

struct CharacterWidthTests {
    @Test func matchesTheWidthOfEveryScalarInTerminalApp() throws {
        let url = try #require(
            Bundle.module.url(forResource: "widths", withExtension: "txt", subdirectory: "Recordings")
        )
        var checked = 0
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: " ")
            let first = try #require(UInt32(fields[0], radix: 16))
            let last = try #require(UInt32(fields[1], radix: 16))
            let width = try #require(Int(fields[2]))
            for value in first ... last {
                if let scalar = Unicode.Scalar(value), scalar.width != width {
                    Issue.record("U+\(String(value, radix: 16)) is \(scalar.width), not \(width)")
                }
                checked += 1
            }
        }
        #expect(checked == 0x11_0000 - 0x80)
    }
}
