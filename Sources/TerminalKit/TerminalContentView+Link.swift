import AppKit
import TerminalCore

extension TerminalContentView {
    struct Link: Equatable {
        struct Span: Equatable {
            var row: Int
            var columns: Range<Int>
        }

        var url: URL
        var spans: [Span]
    }

    enum LinkAction: Equatable {
        case open(URL)
        case reveal(URL)
    }

    private static let schemes: Set<String> = ["http", "https", "mailto", "ftp", "file"]
    private static let launchingExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action", "pkg", "mpkg", "scpt", "scptd", "applescript",
        "jar",
    ]
    private static let pattern = #/(?:https?|ftp|file)://[^\s<>"'`]+|mailto:[^\s<>"'`]+/#.ignoresCase()

    static func action(for url: URL) -> LinkAction? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else {
            return nil
        }
        guard url.isFileURL else {
            return .open(url)
        }
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        let launches =
            launchingExtensions.contains(url.pathExtension.lowercased())
            || !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        return launches ? .reveal(url) : .open(url)
    }

    func link(atRow row: Int, column: Int) -> Link? {
        let terminal = session.terminal
        let lineCount = terminal.scrollback.count + terminal.rows
        guard (0 ..< lineCount).contains(row) else {
            return nil
        }
        let line = { (row: Int) in
            row < terminal.scrollback.count
                ? terminal.scrollback[row] : terminal.screen[row - terminal.scrollback.count]
        }
        var first = row
        while first > 0, row - first < 64, line(first - 1).isWrapped {
            first -= 1
        }
        var last = row
        while last < lineCount - 1, last - row < 64, line(last).isWrapped {
            last += 1
        }
        var cells: [(row: Int, column: Int, cell: Terminal.Cell)] = []
        for row in first ... last {
            let cellsOfRow = line(row)
            for column in cellsOfRow.indices where cellsOfRow[column].width > 0 && cellsOfRow[column] != .padding {
                cells.append((row, column, cellsOfRow[column]))
            }
        }
        guard
            let index = cells.firstIndex(where: {
                $0.row == row && $0.column <= column && column < $0.column + Int($0.cell.width)
            })
        else {
            return nil
        }
        let range: Range<Int>
        let url: URL?
        if case let link = cells[index].cell.style.link, link > 0 {
            let lowerBound = cells[..<index].lastIndex { $0.cell.style.link != link }.map { $0 + 1 } ?? 0
            let upperBound = cells[index...].firstIndex { $0.cell.style.link != link } ?? cells.count
            range = lowerBound ..< upperBound
            url = terminal.links.uri(of: link).flatMap(URL.init(string:))
        } else {
            let characters = cells.map { terminal.character(of: $0.cell) }
            let text = String(characters)
            guard let match = Self.detectedLinks(in: text).first(where: { $0.contains(index) }) else {
                return nil
            }
            range = match
            url = URL(string: String(characters[match]))
        }
        guard let url else {
            return nil
        }
        let spans = Dictionary(grouping: cells[range], by: \.row)
            .map { row, cells in
                Link.Span(
                    row: row,
                    columns: cells[0].column ..< cells[cells.count - 1].column + Int(cells[cells.count - 1].cell.width))
            }
            .sorted { $0.row < $1.row }
        return Link(url: url, spans: spans)
    }

    static func detectedLinks(in text: String) -> [Range<Int>] {
        text.matches(of: pattern)
            .map { match in
                let lowerBound = text.distance(from: text.startIndex, to: match.range.lowerBound)
                var characters = Array(text[match.range])
                while let last = characters.last, shouldTrim(last, from: characters) {
                    characters.removeLast()
                }
                return lowerBound ..< lowerBound + characters.count
            }
    }

    private static func shouldTrim(_ character: Character, from characters: [Character]) -> Bool {
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{", ">": "<"]
        guard let opening = pairs[character] else {
            return ".,;:!?".contains(character)
        }
        return characters.count { $0 == character } > characters.count { $0 == opening }
    }

    func link(at event: NSEvent) -> Link? {
        let location = convert(event.locationInWindow, from: nil)
        return link(
            atRow: Int(floor((location.y - Self.padding) / cellSize.height)),
            column: Int(floor((location.x - Self.padding) / cellSize.width))
        )
    }

    func openLink(at event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), let link = link(at: event) else {
            return false
        }
        if let action = Self.action(for: link.url) {
            performLinkAction(action)
        }
        return true
    }

    func updateHoveredLink(at locationInWindow: CGPoint?, modifierFlags: NSEvent.ModifierFlags) {
        guard modifierFlags.contains(.command), let locationInWindow else {
            hoveredLink = nil
            return
        }
        let location = convert(locationInWindow, from: nil)
        hoveredLink = link(
            atRow: Int(floor((location.y - Self.padding) / cellSize.height)),
            column: Int(floor((location.x - Self.padding) / cellSize.width))
        )
        hoveredLinkRevision = session.revision
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredLink(at: event.locationInWindow, modifierFlags: event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateHoveredLink(at: window?.mouseLocationOutsideOfEventStream, modifierFlags: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredLink = nil
    }
}
