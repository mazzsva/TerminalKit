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
}
