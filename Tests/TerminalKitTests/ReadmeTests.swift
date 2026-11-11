import Foundation
import Testing

struct ReadmeTests {
    @Test func showsTheExampleThatCompiles() throws {
        let tests = URL(filePath: #filePath).deletingLastPathComponent()
        let example = try String(contentsOf: tests.appending(path: "ReadmeExample.swift"), encoding: .utf8)
        let readme = try String(
            contentsOf: tests.appending(path: "../../README.md").standardizedFileURL, encoding: .utf8)
        #expect(readme.contains("```swift\n" + example + "```\n"))
    }

    @Test func namesEachIgnoredSequence() throws {
        let readme = try String(
            contentsOf: URL(filePath: #filePath).appending(path: "../../../README.md").standardizedFileURL,
            encoding: .utf8)
        for sequence in ProgramSessionTests.ignored {
            #expect(readme.contains("`\(sequence)`"), "\(sequence)")
        }
    }
}
