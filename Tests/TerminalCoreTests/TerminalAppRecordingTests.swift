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
        var terminal = terminalLikeTheRecordedWindow()
        let reply = terminal.receive(bytes(recording.input) + Array("\u{1B}[6n".utf8))
        #expect(escaped(reply) == recording.reply)
        #expect(terminal.title == recording.title ?? "")
        #expect(scalars(text(terminal.screen, of: terminal)) == scalars(recording.screen))
        let history = terminal.scrollback + terminal.normalScreenLines + terminal.screen
        #expect(scalars(text(history, of: terminal)) == scalars(recording.history ?? recording.screen))
    }

    func terminalLikeTheRecordedWindow() -> Terminal {
        var terminal = Terminal(columns: 40, rows: 12)
        terminal.windowReport = Terminal.WindowReport(width: 300, height: 197)
        terminal.defaultColors = Terminal.DefaultColors(
            foreground: rgb(0xE6CE, 0xE6CE, 0xE6CE),
            background: rgb(0x213D, 0x2743, 0x33E7),
            cursor: rgb(0x9D2C, 0x9D2C, 0x9D2C),
            selection: rgb(0x3370, 0x4E03, 0x5EBA),
            bold: rgb(0xF165, 0xF165, 0xF165),
            ansi: [
                rgb(0x354E, 0x4245, 0x4BCF), rgb(0xB480, 0x55F1, 0x47F9), rgb(0x6C95, 0xAAD2, 0x7107),
                rgb(0xC4C4, 0xACAC, 0x6262), rgb(0x6D6D, 0x9696, 0xB4B4), rgb(0xBDBD, 0x7B7B, 0xCDCD),
                rgb(0x7C16, 0xCB85, 0xCE42), rgb(0xDE68, 0xE648, 0xEC13), rgb(0x46BD, 0x5CD3, 0x6D12),
                rgb(0xE049, 0x6C9A, 0x5A49), rgb(0x7965, 0xBE4A, 0x7E0D), rgb(0xE5E5, 0xC8C8, 0x7272),
                rgb(0x6767, 0xB5B5, 0xEDED), rgb(0xD3D3, 0x8989, 0xE5E5), rgb(0x848C, 0xDE23, 0xE13A),
                rgb(0xE64A, 0xEF7A, 0xF63D),
            ]
        )
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
