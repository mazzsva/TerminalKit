package struct Terminal: Sendable {
    package struct Cell: Equatable, Sendable {
        package var character: Character = " "
        package var style = Style()
        package var width: UInt8 = 1
    }

    package struct Position: Equatable, Sendable {
        package var row: Int
        package var column: Int
    }

    private struct SavedCursor {
        var position = Position(row: 0, column: 0)
        var style = Style()
        var isWrapPending = false
    }

    private static let tabWidth = 8
    private static let asciiCharacters = (0 ..< 128).map { Character(Unicode.Scalar(UInt8($0))) }
    private static let maximumScrollback = 10_000
    private static let scrollbackTrimCount = 1_000

    package private(set) var columns: Int
    package private(set) var rows: Int
    package private(set) var screen: [[Cell]]
    package private(set) var scrollback: [[Cell]] = []
    package private(set) var removedScrollbackCount = 0
    package private(set) var cursor = Position(row: 0, column: 0)
    package private(set) var title = ""
    package private(set) var usesApplicationCursorKeys = false
    package private(set) var usesBracketedPaste = false
    package private(set) var isCursorVisible = true

    package var isAlternateScreenActive: Bool {
        normalScreen != nil
    }

    private var decoder = UTF8Decoder()
    private var parser = EscapeSequenceParser()
    private var isWrapPending = false
    private var style = Style()
    private var savedCursor = SavedCursor()
    private var scrollRegion: Range<Int>
    private var replies: [UInt8] = []
    private var normalScreen: (lines: [[Cell]], savedCursor: SavedCursor)?

    package init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        screen = Array(repeating: Self.blankLine(columns: columns), count: rows)
        scrollRegion = 0 ..< rows
    }

    package mutating func resize(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        let removedRows = max(cursor.row + 1 - rows, 0)
        if normalScreen == nil {
            keepInScrollback(screen.prefix(removedRows))
        }
        screen = Self.resized(screen, columns: columns, rows: rows, removingFirst: removedRows)
        if var normalScreen {
            let removedNormalRows = max(normalScreen.savedCursor.position.row + 1 - rows, 0)
            keepInScrollback(normalScreen.lines.prefix(removedNormalRows))
            normalScreen.lines = Self.resized(
                normalScreen.lines,
                columns: columns,
                rows: rows,
                removingFirst: removedNormalRows
            )
            normalScreen.savedCursor.position.row -= removedNormalRows
            self.normalScreen = normalScreen
        }
        self.columns = columns
        self.rows = rows
        scrollRegion = 0 ..< rows
        moveCursor(row: cursor.row - removedRows, column: cursor.column)
    }

    @discardableResult
    package mutating func receive(_ bytes: [UInt8]) -> [UInt8] {
        defer { replies.removeAll() }
        for scalar in decoder.decode(bytes) {
            guard let action = parser.advance(scalar) else {
                continue
            }
            switch action {
            case .print(let scalar):
                print(scalar)
            case .execute("\n"):
                lineFeed()
            case .execute("\r"):
                carriageReturn()
            case .execute("\u{8}"):
                moveCursor(row: cursor.row, column: cursor.column - 1)
            case .execute("\t"):
                cursor.column = min((cursor.column / Self.tabWidth + 1) * Self.tabWidth, columns - 1)
            case .escape(intermediates: "", final: "D"):
                lineFeed()
            case .escape(intermediates: "", final: "E"):
                carriageReturn()
                lineFeed()
            case .escape(intermediates: "", final: "M"):
                reverseLineFeed()
            case .escape(intermediates: "", final: "7"):
                saveCursor()
            case .escape(intermediates: "", final: "8"):
                restoreCursor()
            case .controlSequence(let sequence):
                perform(sequence)
            case .operatingSystemCommand(let command):
                perform(command)
            default:
                break
            }
        }
        return replies
    }

    private mutating func perform(_ sequence: EscapeSequenceParser.ControlSequence) {
        guard sequence.intermediates.isEmpty else {
            return
        }
        if sequence.privateMarker == "?", sequence.final == "h" || sequence.final == "l" {
            for mode in sequence.parameters {
                setPrivateMode(mode, isEnabled: sequence.final == "h")
            }
            return
        }
        guard sequence.privateMarker == nil else {
            return
        }
        let count = sequence.parameter(at: 0, default: 1)
        switch sequence.final {
        case "A":
            moveCursor(row: cursor.row - count, column: cursor.column)
        case "B":
            moveCursor(row: cursor.row + count, column: cursor.column)
        case "C":
            moveCursor(row: cursor.row, column: cursor.column + count)
        case "D":
            moveCursor(row: cursor.row, column: cursor.column - count)
        case "E":
            moveCursor(row: cursor.row + count, column: 0)
        case "F":
            moveCursor(row: cursor.row - count, column: 0)
        case "G":
            moveCursor(row: cursor.row, column: count - 1)
        case "H", "f":
            moveCursor(row: count - 1, column: sequence.parameter(at: 1, default: 1) - 1)
        case "d":
            moveCursor(row: count - 1, column: cursor.column)
        case "J":
            eraseInDisplay(sequence.parameter(at: 0, default: 0))
        case "K":
            eraseInLine(sequence.parameter(at: 0, default: 0))
        case "@":
            insertCharacters(count)
        case "P":
            deleteCharacters(count)
        case "X":
            erase(cursor.column ..< min(cursor.column + count, columns), row: cursor.row)
        case "L":
            insertLines(count)
        case "M":
            deleteLines(count)
        case "S":
            scrollRegionUp(count)
        case "T" where sequence.parameters.count <= 1:
            scrollDown(count, in: scrollRegion)
        case "c" where sequence.parameter(at: 0, default: 0) == 0:
            replies += "\u{1B}[?1;2c".utf8
        case "m":
            style.apply(sequence.parameters)
        case "n":
            reportStatus(sequence.parameter(at: 0, default: 0))
        case "r":
            setScrollRegion(top: count - 1, bottom: min(sequence.parameter(at: 1, default: rows), rows))
        case "s" where sequence.parameters.isEmpty:
            saveCursor()
        case "u" where sequence.parameters.isEmpty:
            restoreCursor()
        default:
            break
        }
    }

    private mutating func perform(_ command: String) {
        let parts = command.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, parts[0] == "0" || parts[0] == "2" {
            title = String(parts[1])
        }
    }

    private mutating func print(_ scalar: Unicode.Scalar) {
        let width = columns > 1 ? max(scalar.width, 1) : 1
        if isWrapPending || cursor.column + width > columns {
            carriageReturn()
            lineFeed()
        }
        let character = scalar.isASCII ? Self.asciiCharacters[Int(scalar.value)] : Character(scalar)
        screen[cursor.row][cursor.column] = Cell(character: character, style: style, width: UInt8(width))
        if width == 2 {
            screen[cursor.row][cursor.column + 1] = Cell(style: style, width: 0)
        }
        if cursor.column + width == columns {
            cursor.column = columns - 1
            isWrapPending = true
        } else {
            cursor.column += width
        }
    }

    private mutating func lineFeed() {
        isWrapPending = false
        if cursor.row == scrollRegion.upperBound - 1 {
            scrollRegionUp(1)
        } else if cursor.row < rows - 1 {
            cursor.row += 1
        }
    }

    private mutating func insertCharacters(_ count: Int) {
        isWrapPending = false
        let count = min(count, columns - cursor.column)
        screen[cursor.row].insert(contentsOf: repeatElement(blank, count: count), at: cursor.column)
        screen[cursor.row].removeLast(count)
    }

    private mutating func deleteCharacters(_ count: Int) {
        isWrapPending = false
        let count = min(count, columns - cursor.column)
        screen[cursor.row].removeSubrange(cursor.column ..< cursor.column + count)
        screen[cursor.row].append(contentsOf: repeatElement(blank, count: count))
    }

    private mutating func insertLines(_ count: Int) {
        guard scrollRegion.contains(cursor.row) else {
            return
        }
        scrollDown(count, in: cursor.row ..< scrollRegion.upperBound)
        carriageReturn()
    }

    private mutating func deleteLines(_ count: Int) {
        guard scrollRegion.contains(cursor.row) else {
            return
        }
        scrollUp(count, in: cursor.row ..< scrollRegion.upperBound)
        carriageReturn()
    }

    private mutating func setScrollRegion(top: Int, bottom: Int) {
        guard top < bottom - 1 else {
            return
        }
        scrollRegion = top ..< bottom
        moveCursor(row: 0, column: 0)
    }

    private mutating func keepInScrollback(_ lines: ArraySlice<[Cell]>) {
        scrollback += lines
        if scrollback.count > Self.maximumScrollback + Self.scrollbackTrimCount {
            removedScrollbackCount += scrollback.count - Self.maximumScrollback
            scrollback.removeFirst(scrollback.count - Self.maximumScrollback)
        }
    }

    private mutating func scrollRegionUp(_ count: Int) {
        if scrollRegion.lowerBound == 0, normalScreen == nil {
            keepInScrollback(screen.prefix(min(count, scrollRegion.count)))
        }
        scrollUp(count, in: scrollRegion)
    }

    private mutating func scrollUp(_ count: Int, in region: Range<Int>) {
        let count = min(count, region.count)
        screen.removeSubrange(region.lowerBound ..< region.lowerBound + count)
        screen.insert(contentsOf: blankLines(count), at: region.upperBound - count)
    }

    private mutating func scrollDown(_ count: Int, in region: Range<Int>) {
        let count = min(count, region.count)
        screen.removeSubrange(region.upperBound - count ..< region.upperBound)
        screen.insert(contentsOf: blankLines(count), at: region.lowerBound)
    }

    private mutating func reverseLineFeed() {
        isWrapPending = false
        if cursor.row == scrollRegion.lowerBound {
            scrollDown(1, in: scrollRegion)
        } else if cursor.row > 0 {
            cursor.row -= 1
        }
    }

    private mutating func carriageReturn() {
        isWrapPending = false
        cursor.column = 0
    }

    private mutating func moveCursor(row: Int, column: Int) {
        isWrapPending = false
        cursor = Position(row: min(max(row, 0), rows - 1), column: min(max(column, 0), columns - 1))
    }

    private mutating func setPrivateMode(_ mode: Int, isEnabled: Bool) {
        switch (mode, isEnabled) {
        case (1, _):
            usesApplicationCursorKeys = isEnabled
        case (25, _):
            isCursorVisible = isEnabled
        case (2004, _):
            usesBracketedPaste = isEnabled
        case (47, true), (1047, true):
            enterAlternateScreen()
        case (47, false), (1047, false):
            exitAlternateScreen()
        case (1049, true):
            saveCursor()
            enterAlternateScreen()
        case (1049, false):
            exitAlternateScreen()
            restoreCursor()
        default:
            break
        }
    }

    private mutating func enterAlternateScreen() {
        guard normalScreen == nil else {
            return
        }
        normalScreen = (screen, savedCursor)
        screen = blankLines(rows)
        savedCursor = SavedCursor()
    }

    private mutating func exitAlternateScreen() {
        guard let normalScreen else {
            return
        }
        (screen, savedCursor) = normalScreen
        self.normalScreen = nil
    }

    private mutating func reportStatus(_ request: Int) {
        switch request {
        case 5:
            replies += "\u{1B}[0n".utf8
        case 6:
            replies += "\u{1B}[\(cursor.row + 1);\(cursor.column + 1)R".utf8
        default:
            break
        }
    }

    private mutating func saveCursor() {
        savedCursor = SavedCursor(position: cursor, style: style, isWrapPending: isWrapPending)
    }

    private mutating func restoreCursor() {
        moveCursor(row: savedCursor.position.row, column: savedCursor.position.column)
        style = savedCursor.style
        isWrapPending = savedCursor.isWrapPending
    }

    private mutating func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseInLine(0)
            for row in cursor.row + 1 ..< rows {
                erase(0 ..< columns, row: row)
            }
        case 1:
            for row in 0 ..< cursor.row {
                erase(0 ..< columns, row: row)
            }
            eraseInLine(1)
        case 2:
            for row in 0 ..< rows {
                erase(0 ..< columns, row: row)
            }
        default:
            break
        }
    }

    private mutating func eraseInLine(_ mode: Int) {
        switch mode {
        case 0:
            erase(cursor.column ..< columns, row: cursor.row)
        case 1:
            erase(0 ..< cursor.column + 1, row: cursor.row)
        case 2:
            erase(0 ..< columns, row: cursor.row)
        default:
            break
        }
    }

    private mutating func erase(_ range: Range<Int>, row: Int) {
        isWrapPending = false
        screen[row].replaceSubrange(range, with: repeatElement(blank, count: range.count))
    }

    private var blank: Cell {
        Cell(style: Style(background: style.background))
    }

    private func blankLines(_ count: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: blank, count: columns), count: count)
    }

    private static func resized(_ screen: [[Cell]], columns: Int, rows: Int, removingFirst removedRows: Int)
        -> [[Cell]]
    {
        let lines = screen.dropFirst(removedRows).prefix(rows)
            .map { line in
                Array(line.prefix(columns)) + blankLine(columns: max(columns - line.count, 0))
            }
        return lines + Array(repeating: blankLine(columns: columns), count: rows - lines.count)
    }

    private static func blankLine(columns: Int) -> [Cell] {
        Array(repeating: Cell(), count: columns)
    }
}
