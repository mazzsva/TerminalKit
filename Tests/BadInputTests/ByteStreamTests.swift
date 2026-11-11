import AppKit
import Testing

@testable import TerminalCore
@testable import TerminalKit

@Suite(.timeLimit(.minutes(5)))
struct ByteStreamTests {
    static let seed: UInt64 = 0x7E57_5EED
    static let streamCount = 1_000_000
    static let chunkSize = 10_000
    static let drawInterval = 500
    static let yieldInterval = 10
    static let maximumReplyBytesPerByte = 72

    @MainActor private static let view = TerminalContentView(session: TerminalSession())

    @Test(arguments: 0 ..< streamCount / chunkSize)
    func receivesTheStreamsWithNoCrash(chunk: Int) async throws {
        try await Task(priority: .background) { try await Self.receiveTheStreams(chunk: chunk) }.value
    }

    private static func receiveTheStreams(chunk: Int) async throws {
        var streams = ByteStreams(seed: seed, chunk: chunk)
        var size = streams.size()
        var terminal = Terminal(columns: size.columns, rows: size.rows)
        terminal.defaultColors = Terminal.DefaultColors(
            foreground: Terminal.RGB(red: 1, green: 2, blue: 3),
            background: Terminal.RGB(red: 4, green: 5, blue: 6),
            cursor: Terminal.RGB(red: 7, green: 8, blue: 9)
        )
        for index in chunk * chunkSize ..< (chunk + 1) * chunkSize {
            let (resize, bytes) = streams.next()
            if let resize {
                size = resize
                terminal.resize(columns: size.columns, rows: size.rows)
            }
            let replies = terminal.receive(bytes)
            let failure =
                replies.count > maximumReplyBytesPerByte * bytes.count
                ? "\(replies.count) reply bytes" : problem(in: terminal, size: size)
            if let failure {
                Issue.record("Seed \(seed), stream \(index): \(failure)")
                return
            }
            if index % drawInterval == chunk * drawInterval * chunkSize / streamCount {
                try await draw(terminal)
            } else if index % yieldInterval == 0 {
                await Task.yield()
            }
        }
    }

    private static func problem(in terminal: Terminal, size: (columns: Int, rows: Int)) -> String? {
        if terminal.columns != size.columns || terminal.rows != size.rows {
            return "size \(terminal.columns) by \(terminal.rows)"
        }
        if terminal.screen.count != terminal.rows {
            return "\(terminal.screen.count) screen lines"
        }
        if let row = terminal.screen.firstIndex(where: { $0.count < terminal.columns }) {
            return "\(terminal.screen[row].count) cells in row \(row)"
        }
        if !(0 ..< terminal.rows).contains(terminal.cursor.row)
            || !(0 ..< terminal.columns).contains(terminal.cursor.column)
        {
            return "cursor at \(terminal.cursor)"
        }
        if terminal.normalScreenLines.count > (terminal.isAlternateScreenActive ? terminal.rows : 0) {
            return "\(terminal.normalScreenLines.count) normal screen lines"
        }
        return nil
    }

    @MainActor
    private static func draw(_ terminal: Terminal) throws {
        view.session.liveTerminal = terminal
        let top = view.rect(row: terminal.scrollback.count, columns: 0 ..< terminal.columns)
        let screen = top.union(top.offsetBy(dx: 0, dy: CGFloat(terminal.rows - 1) * top.height))
        view.frame = NSRect(
            x: 0, y: 0, width: screen.maxX + TerminalContentView.padding,
            height: screen.maxY + TerminalContentView.bottomPadding)
        view.cacheDisplay(in: screen, to: try #require(view.bitmapImageRepForCachingDisplay(in: screen)))
        _ = view.accessibilityValue()
    }
}

struct ByteStreams {
    private static let text = [
        "\u{4E2D}\u{6587}", "e\u{301}", "\u{915}\u{94D}\u{937}\u{93F}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
        "\u{2764}\u{FE0F}", "\u{1F44D}\u{1F3FD}", "\u{1F1EF}\u{1F1F5}", "1\u{FE0F}\u{20E3}",
        "\u{1F3F4}\u{E0067}\u{E007F}",
        "\u{5D0}\u{5D1} \u{627}\u{644}", "\u{202E}x\u{2067}", "\u{200B}\u{FEFF}", "\u{1F1E6}", "\u{FE0F}", "\u{200D}",
        "\u{301}\u{301}\u{301}", "\u{FF21}", "\u{3000}", "lqqk", "\u{10FFFF}", "\u{E000}",
    ]
    private static let invalidText: [[UInt8]] = [
        [0x80], [0xBF], [0xC0, 0xAF], [0xC2], [0xE4, 0xB8], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xF0, 0x9F],
        [0xFE], [0xFF], [0xF8, 0x88, 0x80, 0x80, 0x80], [0xC2, 0x9B], [0xC2, 0x9D], [0xC2, 0x90], [0xC2, 0x9C], [0x9B],
    ]
    private static let controls = ["\r", "\n", "\r\n", "\t", "\u{8}", "\u{7}", "\u{B}", "\u{C}", "\u{18}", "\u{1A}"]
    private static let escapes = ["D", "E", "H", "M", "7", "8", "=", ">", "(0", "(B", "c", "\\", "#8", " F"]
    private static let finals = Array("ABCDEFG`IZgHfdJK@PXLMSTchlmnrt".unicodeScalars)
    private static let modes = [1, 5, 7, 25, 1000, 1002, 1003, 1004, 1006, 2004, 1049, 1049, 1049, 47, 1047, 2026]
    private static let largeNumbers = ["2147483647", "2147483648", "4294967296", "99999999999999999999999"]
    private static let commands = ["0", "2", "7", "4", "10", "11", "12", "112", "1", "8", "52", "133", "", "x"]
    private static let commandTexts = [
        "?", "?;?;?", "rgb:ff/00/7f", "rgb:fff/0/1234", "rgb: f/1/2", "#abc", "#123456789abc", "#12", "rgbi:0.5/1/0",
        "rgb:zz/1/2", "1;rgb:1/2/3;300;#fff", "255;?", "file://localhost/tmp/a%20b", "file:///tmp", "file://host/x",
        "file:///%ZZ", "http://x/", "title", "",
    ]

    private var random: SplitMix64
    private var pending: [UInt8] = []

    init(seed: UInt64, chunk: Int) {
        var seeds = SplitMix64(state: seed &+ UInt64(chunk))
        random = SplitMix64(state: seeds.next())
    }

    mutating func size() -> (columns: Int, rows: Int) {
        (int(pick([1 ... 4, 5 ... 80, 1 ... 200])), int(pick([1 ... 4, 5 ... 24, 1 ... 60])))
    }

    mutating func next() -> (resize: (columns: Int, rows: Int)?, bytes: [UInt8]) {
        let resize = chance(0.03) ? size() : nil
        let length = chance(0.005) ? int(1_000 ... 8_000) : int(1 ... int(1 ... 200))
        var bytes = pending
        pending = []
        if chance(0.5) {
            while bytes.count < length {
                bytes.append(UInt8.random(in: 0 ... 255, using: &random))
            }
            return (resize, bytes)
        }
        while bytes.count < length {
            bytes += item()
        }
        if chance(0.5) {
            pending = Array(bytes[length...])
            bytes.removeSubrange(length...)
        }
        return (resize, bytes)
    }

    private mutating func item() -> [UInt8] {
        switch int(0 ... 99) {
        case 0 ..< 25:
            Array(text().utf8)
        case 25 ..< 35:
            chance(0.8) ? Array(pick(Self.controls).utf8) : [UInt8(int(0 ... 31))]
        case 35 ..< 38:
            pick(Self.invalidText)
        case 38 ..< 46:
            escape()
        case 46 ..< 85:
            controlSequence()
        case 85 ..< 95:
            operatingSystemCommand()
        default:
            string()
        }
    }

    private mutating func text() -> String {
        switch int(0 ... 3) {
        case 0:
            String(repeating: pick(Array("abc xyz-|_".unicodeScalars)).description, count: int(1 ... 30))
        case 1:
            pick(Self.text)
        case 2:
            String(Unicode.Scalar(UInt32(int(0xA0 ... 0x2_FFFF))) ?? "?")
        default:
            String((0 ..< int(1 ... 20)).map { _ in Character(Unicode.Scalar(UInt8(int(0x20 ... 0x7E)))) })
        }
    }

    private mutating func escape() -> [UInt8] {
        if chance(0.7) {
            return [0x1B] + pick(Self.escapes).utf8
        }
        return [0x1B] + (0 ..< int(0 ... 3)).map { _ in UInt8(int(0x20 ... 0x2F)) } + [UInt8(int(0x30 ... 0x7E))]
    }

    private mutating func controlSequence() -> [UInt8] {
        var sequence = "\u{1B}["
        switch int(0 ... 9) {
        case 0, 1:
            let modes = (0 ..< int(1 ... 3)).map { _ in String(pick(Self.modes)) }
            sequence += "?\(modes.joined(separator: ";"))\(chance(0.6) ? "h" : "l")"
        case 2:
            sequence += pick([
                "6n", "5n", "?6n", "c", "0c", ">c", ">0c", ">4;\(int(0 ... 3))m", ">4n", "?4m", "\(int(0 ... 7)) q",
                "!p", "22;\(int(0 ... 3))t", "23;\(int(0 ... 3))t", "\(int(0 ... 3))J", "3J",
            ])
        case 3:
            sequence += "\(int(0 ... 61));\(int(0 ... 61))r"
        case 4:
            sequence += "\(chance(0.000_02) ? 1_000_000 : int(0 ... 300))b"
        default:
            if chance(0.3) {
                sequence += pick(["?", "?", ">", "<", "="])
            }
            let count = chance(0.05) ? int(33 ... 40) : int(0 ... 4)
            sequence += (0 ..< count).map { _ in parameter() }.joined(separator: ";")
            if chance(0.05) {
                sequence += chance(0.5) ? pick([" ", "!", "$"]) : String(Unicode.Scalar(UInt8(int(0x20 ... 0x2F))))
            }
            let final = chance(0.8) ? pick(Self.finals) : Unicode.Scalar(UInt8(int(0x40 ... 0x7E)))
            sequence += String(final == "b" ? "m" : final)
        }
        return Array(sequence.utf8)
    }

    private mutating func parameter() -> String {
        switch int(0 ... 9) {
        case 0:
            ""
        case 1:
            "0"
        case 2:
            "1"
        case 3:
            pick(Self.largeNumbers)
        case 4:
            pick(["4:3", "4:0", "38:2::1:2:3", "38:5:9", ":", "1:", "::::"])
        case 5:
            pick(["38;5;\(int(0 ... 300))", "48;2;\(int(0 ... 300));2;3", "38;2", "48;5"])
        default:
            String(int(0 ... 300))
        }
    }

    private mutating func operatingSystemCommand() -> [UInt8] {
        var bytes: [UInt8] = [0x1B, 0x5D] + (chance(0.9) ? pick(Self.commands) : pick(Self.largeNumbers)).utf8
        if chance(0.9) {
            bytes.append(0x3B)
            switch int(0 ... 9) {
            case 0:
                bytes += [UInt8](repeating: UInt8(int(0x20 ... 0x7E)), count: int(1_000 ... 6_000))
            case 1:
                bytes += (0 ..< int(1 ... 40)).map { _ in UInt8.random(in: 0 ... 255, using: &random) }
            case 2 ... 4:
                bytes += text().utf8
            default:
                bytes += pick(Self.commandTexts).utf8
            }
        }
        return bytes + terminator()
    }

    private mutating func string() -> [UInt8] {
        [0x1B, pick(Array("PX^_".utf8))] + text().utf8 + (chance(0.3) ? [UInt8(int(0 ... 31))] : []) + terminator()
    }

    private mutating func terminator() -> [UInt8] {
        pick([[0x07], [0x07], [0x1B, 0x5C], [0x1B, 0x5C], [], [0x18], [0xC2, 0x9C]])
    }

    private mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &random)
    }

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0 ..< 1, using: &random) < probability
    }

    private mutating func pick<Element>(_ elements: [Element]) -> Element {
        elements[int(0 ... elements.count - 1)]
    }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ value >> 30) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ value >> 27) &* 0x94D0_49BB_1331_11EB
        return value ^ value >> 31
    }
}
