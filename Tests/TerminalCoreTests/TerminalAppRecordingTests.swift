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
        var steps: [Step]?

        struct Step: Decodable, Sendable {
            var columns: Int
            var rows: Int
            var input: String?
        }

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
        var terminal = terminalLikeTheRecordedWindow()
        let reply = play(recording, in: &terminal)
        #expect(escaped(reply) == recording.reply)
        #expect(terminal.title == recording.title ?? "")
        #expect(scalars(text(terminal.screen, of: terminal)) == scalars(recording.screen))
        let history = terminal.scrollback + terminal.normalScreenLines + terminal.screen
        #expect(scalars(text(history, of: terminal)) == scalars(recording.history ?? recording.screen))
    }

    func play(_ recording: Recording, in terminal: inout Terminal) -> [UInt8] {
        guard let steps = recording.steps else {
            return terminal.receive(bytes(recording.input) + Array("\u{1B}[6n".utf8))
        }
        var reply = terminal.receive(bytes(recording.input))
        for step in steps {
            terminal.resize(columns: step.columns, rows: step.rows)
            reply += terminal.receive(bytes(step.input ?? ""))
        }
        return reply + terminal.receive(Array("\u{1B}[6n".utf8))
    }

    func terminalLikeTheRecordedWindow() -> Terminal {
        var terminal = Terminal(columns: 40, rows: 12)
        terminal.defaultColors = Terminal.DefaultColors(
            foreground: rgb(0xE6CE, 0xE6CE, 0xE6CE),
            background: rgb(0x213D, 0x2743, 0x33E7),
            cursor: rgb(0x9D2C, 0x9D2C, 0x9D2C)
        )
        _ = terminal.receive(
            Array("\u{1B}[3g\u{1B}[9G\u{1B}H\u{1B}[17G\u{1B}H\u{1B}[25G\u{1B}H\u{1B}[33G\u{1B}H\u{1B}[H".utf8))
        return terminal
    }

    func rgb(_ red: UInt16, _ green: UInt16, _ blue: UInt16) -> Terminal.RGB {
        Terminal.RGB(red: red, green: green, blue: blue)
    }

    func scalars(_ lines: [String]) -> [[Unicode.Scalar]] {
        lines.map { Array($0.unicodeScalars) }
    }

    func bytes(_ text: String) -> [UInt8] {
        let source = Array(text.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 3 < source.count, source[index + 1] == 0x78,
                let high = Character(UnicodeScalar(source[index + 2])).hexDigitValue,
                let low = Character(UnicodeScalar(source[index + 3])).hexDigitValue
            {
                bytes.append(UInt8(high * 16 + low))
                index += 4
            } else {
                bytes.append(source[index])
                index += 1
            }
        }
        return bytes
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
            let string = line[..<end].filter(\.isText).map(terminal.character(of:)).joined()
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
