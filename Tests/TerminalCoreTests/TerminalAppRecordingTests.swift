import Foundation
import Testing

@testable import TerminalCore

struct TerminalAppRecordingTests {
    struct Recording: Decodable, CustomTestStringConvertible, Sendable {
        var name: String
        var input: String
        var reply: String
        var screen: [String]
        var history: [String]?
        var title: String?

        var testDescription: String {
            name
        }
    }

    static let recordings: [Recording] = {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Recordings") ?? []
        return urls.sorted { $0.path < $1.path }
            .flatMap { url -> [Recording] in
                do {
                    return try JSONDecoder().decode([Recording].self, from: Data(contentsOf: url))
                } catch {
                    fatalError("\(url.lastPathComponent): \(error)")
                }
            }
    }()

    @Test func loadsTheRecordings() {
        #expect(!Self.recordings.isEmpty)
    }

    @Test(arguments: recordings)
    func matchesTerminalApp(recording: Recording) {
        var terminal = Terminal(columns: 40, rows: 12)
        let reply = terminal.receive(bytes(recording.input) + Array("\u{1B}[6n".utf8))
        #expect(escaped(reply) == recording.reply)
        #expect(terminal.title == recording.title ?? "")
        #expect(text(terminal.screen, of: terminal) == recording.screen)
        #expect(text(terminal.scrollback + terminal.screen, of: terminal) == recording.history ?? recording.screen)
    }

    func bytes(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var rest = Substring(text)
        while let range = rest.range(of: #"\\x[0-9A-Fa-f]{2}"#, options: .regularExpression) {
            bytes += Array(rest[..<range.lowerBound].utf8)
            bytes.append(UInt8(rest[range].dropFirst(2), radix: 16) ?? 0)
            rest = rest[range.upperBound...]
        }
        return bytes + Array(rest.utf8)
    }

    func escaped(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            (0x20 ..< 0x7F).contains(byte) && byte != 0x5C
                ? String(UnicodeScalar(byte)) : String(format: "\\x%02X", byte)
        }
        .joined()
    }

    func text(_ lines: [Terminal.Line], of terminal: Terminal) -> [String] {
        var text: [String] = []
        var isContinuation = false
        for line in lines {
            let end = (line.lastIndex(where: \.isWritten) ?? -1) + 1
            let string = String(line[..<end].filter(\.isText).map(terminal.character(of:)))
            if isContinuation, let last = text.popLast() {
                text.append(last + string)
            } else {
                text.append(string)
            }
            isContinuation = line.isWrapped
        }
        while text.last == "" {
            text.removeLast()
        }
        return text
    }
}
