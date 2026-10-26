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
        "jar", "webloc", "fileloc", "inetloc", "mobileconfig", "prefpane", "saver",
    ]
    private static let pattern = #/(?:https?|ftp|file)://[^\s<>"'`]+|mailto:[^\s<>"'`]+/#.ignoresCase()

    static func performWithWorkspace(_ action: LinkAction) {
        switch action {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .reveal(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func action(for url: URL) -> LinkAction? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else {
            return nil
        }
        guard url.isFileURL else {
            return .open(url)
        }
        let resolved = url.resolvingSymlinksInPath()
        let path = resolved.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard Terminal.isLocal(url), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        let launches =
            launchingExtensions.contains(resolved.pathExtension.lowercased())
            || (try? resolved.resourceValues(forKeys: [.isApplicationKey]).isApplication) == true
            || !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        return launches ? .reveal(url) : .open(url)
    }

    func rows(ofLineAt row: Int, limit: Int, in terminal: Terminal) -> ClosedRange<Int> {
        let screenStart = terminal.isAlternateScreenActive ? terminal.scrollback.count : 0
        let bounds = row < screenStart ? 0 ..< screenStart : screenStart ..< terminal.scrollback.count + terminal.rows
        var first = row
        while first > bounds.lowerBound, row - first < limit, line(at: first - 1, in: terminal).isWrapped {
            first -= 1
        }
        var last = row
        while last < bounds.upperBound - 1, last - row < limit, line(at: last, in: terminal).isWrapped {
            last += 1
        }
        return first ... last
    }

    func cells(
        atRow row: Int, column: Int, in terminal: Terminal
    ) -> (cells: [(row: Int, column: Int, cell: Terminal.Cell)], index: Int)? {
        guard (0 ..< terminal.scrollback.count + terminal.rows).contains(row) else {
            return nil
        }
        var cells: [(row: Int, column: Int, cell: Terminal.Cell)] = []
        for row in rows(ofLineAt: row, limit: 64, in: terminal) {
            let cellsOfRow = line(at: row, in: terminal)
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
        return (cells, index)
    }

    func link(atRow row: Int, column: Int) -> Link? {
        let terminal = session.terminal
        guard let (cells, index) = cells(atRow: row, column: column, in: terminal) else {
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
            var text = String.UnicodeScalarView()
            var starts: [Int] = []
            var count = 0
            for cell in cells {
                let scalars = terminal.character(of: cell.cell).unicodeScalars
                starts.append(count)
                count += scalars.count
                text.append(contentsOf: scalars)
            }
            let offset = starts[index]
            guard
                let match = Self.detectedLinks(in: String(text)).first(where: { $0.contains(offset) }),
                let lowerBound = starts.firstIndex(of: match.lowerBound)
            else {
                return nil
            }
            range = lowerBound ..< (starts[lowerBound...].firstIndex { $0 >= match.upperBound } ?? cells.count)
            url = URL(string: String(cells[range].map { terminal.character(of: $0.cell) }))
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
        let scalars = text.unicodeScalars
        var position = scalars.startIndex
        var offset = 0
        return text.matches(of: pattern.matchingSemantics(.unicodeScalar))
            .map { match in
                offset += scalars.distance(from: position, to: match.range.lowerBound)
                position = match.range.lowerBound
                let lowerBound = offset
                var characters = scalars[match.range].map(Character.init)
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
        if event.clickCount == 1, let action = Self.action(for: link.url) {
            performLinkAction(action)
        }
        return true
    }

    func updateHoveredLink(at locationInWindow: CGPoint?, modifierFlags: NSEvent.ModifierFlags) {
        guard let location = locationInWindow.map({ convert($0, from: nil) }),
            visibleRect.intersection(bounds).contains(location)
        else {
            hoveredLink = nil
            return
        }
        let oldValue = hoveredLink
        hoveredLink =
            modifierFlags.contains(.command)
            ? link(
                atRow: Int(floor((location.y - Self.padding) / cellSize.height)),
                column: Int(floor((location.x - Self.padding) / cellSize.width))
            ) : nil
        hoveredLinkRevision = session.revision
        if hoveredLink != oldValue {
            updatePointer()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updatePointer()
    }

    private func updatePointer() {
        (hoveredLink == nil ? NSCursor.iBeam : .pointingHand).set()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if reportsMouse(for: event), session.liveTerminal.mouseTracking == .anyMotion,
            visibleRect.intersection(bounds).contains(location),
            mousePosition(of: event) != lastMousePosition
        {
            reportMouse(event, button: 35)
        }
        updateHoveredLink(at: event.locationInWindow, modifierFlags: event.modifierFlags)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateHoveredLink(at: window?.mouseLocationOutsideOfEventStream, modifierFlags: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredLink = nil
        lastMousePosition = nil
    }
}
