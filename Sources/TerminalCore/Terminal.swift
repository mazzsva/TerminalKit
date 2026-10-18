package struct Terminal: Sendable {
    package struct Position: Equatable, Sendable {
        package var row: Int
        package var column: Int

        package init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    private struct SavedCursor {
        var position = Position(row: 0, column: 0)
        var style = Style()
        var isWrapPending = false
        var usesLineDrawing = false
    }

    private static let tabWidth = 8
    private static let maximumScrollback = 10_000
    private static let scrollbackTrimCount = 1_000

    package private(set) var columns: Int
    package private(set) var rows: Int
    package private(set) var screen: [Line]
    package private(set) var scrollback: [Line] = []
    package private(set) var removedScrollbackCount = 0
    package private(set) var cursor = Position(row: 0, column: 0)
    package private(set) var usesApplicationCursorKeys = false
    package private(set) var usesBracketedPaste = false
    package private(set) var isCursorVisible = true
    package private(set) var title = ""
    package private(set) var mouseTracking = MouseTracking.off
    private(set) var usesSGRMouseEncoding = false

    package var isAlternateScreenActive: Bool {
        normalScreen != nil
    }
    private var usesAutowrap = true
    private var usesInsertMode = false

    private var decoder = UTF8Decoder()
    private var parser = EscapeSequenceParser()
    private var isWrapPending = false
    private var style = Style()
    private var usesLineDrawing = false
    private var lastCharacter: Unicode.Scalar?
    private var savedCursor = SavedCursor()
    private var scrollRegion: Range<Int>
    private var tabStops: [Bool]
    private var replies: [UInt8] = []
    private var normalScreen: (lines: [Line], savedCursor: SavedCursor)?

    package init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        screen = Array(repeating: Self.blankLine(columns: columns), count: rows)
        scrollRegion = 0 ..< rows
        tabStops = Self.defaultTabStops(0 ..< columns)
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
        tabStops =
            columns > self.columns
            ? tabStops + Self.defaultTabStops(self.columns ..< columns) : Array(tabStops.prefix(columns))
        self.columns = columns
        self.rows = rows
        scrollRegion = 0 ..< rows
        moveCursor(row: cursor.row - removedRows, column: cursor.column)
    }

    package mutating func receive(_ bytes: [UInt8]) -> [UInt8] {
        defer { replies.removeAll() }
        for scalar in decoder.decode(bytes) {
            guard let action = parser.advance(scalar) else {
                continue
            }
            switch action {
            case .print(let scalar):
                print(usesLineDrawing ? scalar.lineDrawingCharacter : scalar)
            case .execute("\n"), .execute("\u{B}"), .execute("\u{C}"):
                lineFeed()
            case .execute("\r"):
                carriageReturn()
            case .execute("\u{8}"):
                moveCursor(row: cursor.row, column: cursor.column - 1)
            case .execute("\t"):
                moveForward(tabStops: 1)
            case .escape(intermediates: "", final: "D"):
                lineFeed()
            case .escape(intermediates: "", final: "E"):
                carriageReturn()
                lineFeed()
            case .escape(intermediates: "", final: "c"):
                reset()
            case .escape(intermediates: "", final: "H"):
                tabStops[cursor.column] = true
            case .escape(intermediates: "", final: "M"):
                reverseLineFeed()
            case .escape(intermediates: "(", final: "0"):
                usesLineDrawing = true
            case .escape(intermediates: "(", final: "B"):
                usesLineDrawing = false
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
        case "I":
            moveForward(tabStops: count)
        case "Z":
            moveBackward(tabStops: count)
        case "g":
            clearTabStops(sequence.parameter(at: 0, default: 0))
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
        case "b":
            if let lastCharacter {
                for _ in 0 ..< count {
                    print(lastCharacter)
                }
            }
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
        case "h" where sequence.parameters.contains(4):
            usesInsertMode = true
        case "l" where sequence.parameters.contains(4):
            usesInsertMode = false
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

    private mutating func print(_ scalar: Unicode.Scalar) {
        guard scalar.width > 0 else {
            combine(scalar)
            return
        }
        lastCharacter = scalar
        let width = columns > 1 ? scalar.width : 1
        if isWrapPending || cursor.column + width > columns {
            if usesAutowrap {
                screen[cursor.row].isWrapped = true
                carriageReturn()
                lineFeed()
            } else {
                cursor.column = columns - width
            }
        }
        if usesInsertMode {
            insertCharacters(width)
        }
        for column in cursor.column ..< cursor.column + width {
            clearWideCharacter(at: column)
        }
        screen[cursor.row][cursor.column] = Cell(scalar: scalar, style: style, width: UInt8(width))
        if width == 2 {
            screen[cursor.row][cursor.column + 1] = Cell(style: style, width: 0)
        }
        if cursor.column + width == columns {
            cursor.column = columns - 1
            isWrapPending = usesAutowrap
        } else {
            cursor.column += width
        }
    }

    private mutating func clearWideCharacter(at column: Int) {
        switch screen[cursor.row][column].width {
        case 0 where column > 0:
            screen[cursor.row][column - 1] = blank
        case 2 where column + 1 < columns:
            screen[cursor.row][column + 1] = blank
        default:
            break
        }
    }

    private mutating func combine(_ scalar: Unicode.Scalar) {
        var column = isWrapPending ? cursor.column : cursor.column - 1
        if column > 0, screen[cursor.row][column].width == 0 {
            column -= 1
        }
        guard column >= 0 else {
            return
        }
        var text = String(screen[cursor.row][column].character)
        text.unicodeScalars.append(scalar)
        if let character = text.first, text.count == 1 {
            screen[cursor.row][column].character = character
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
        for column in [cursor.column, cursor.column + count, columns] {
            blankBrokenWideCharacter(at: column, row: cursor.row)
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        isWrapPending = false
        let count = min(count, columns - cursor.column)
        screen[cursor.row].removeSubrange(cursor.column ..< cursor.column + count)
        screen[cursor.row].append(contentsOf: repeatElement(blank, count: count))
        blankBrokenWideCharacter(at: cursor.column, row: cursor.row)
    }

    private mutating func blankBrokenWideCharacter(at column: Int, row: Int) {
        if column > 0, screen[row][column - 1].width == 2, column == columns || screen[row][column].width != 0 {
            screen[row][column - 1] = blank
        }
        if column < columns, screen[row][column].width == 0, column == 0 || screen[row][column - 1].width != 2 {
            screen[row][column] = blank
        }
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

    private mutating func keepInScrollback(_ lines: ArraySlice<Line>) {
        for line in lines {
            let end = line.isWrapped ? line.count : (line.lastIndex { $0 != Cell() } ?? -1) + 1
            scrollback.append(end == line.count ? line : Line(line[..<end]))
        }
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
        unwrapLine(before: region.lowerBound)
        if region.upperBound < rows {
            unwrapLine(before: region.upperBound - count)
        }
    }

    private mutating func scrollDown(_ count: Int, in region: Range<Int>) {
        let count = min(count, region.count)
        screen.removeSubrange(region.upperBound - count ..< region.upperBound)
        screen.insert(contentsOf: blankLines(count), at: region.lowerBound)
        unwrapLine(before: region.lowerBound)
        unwrapLine(before: region.upperBound)
    }

    private mutating func unwrapLine(before row: Int) {
        if row > 0 {
            screen[row - 1].isWrapped = false
        }
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

    private mutating func perform(_ command: String) {
        let parts = command.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, parts[0] == "0" || parts[0] == "2" {
            title = String(parts[1])
        }
    }

    private mutating func reset() {
        var terminal = Terminal(columns: columns, rows: rows)
        terminal.title = title
        terminal.scrollback = scrollback
        terminal.removedScrollbackCount = removedScrollbackCount
        terminal.decoder = decoder
        terminal.replies = replies
        self = terminal
    }

    private mutating func moveForward(tabStops count: Int) {
        for _ in 0 ..< min(count, columns) {
            cursor.column = tabStops[(cursor.column + 1)...].firstIndex(of: true) ?? columns - 1
        }
    }

    private mutating func moveBackward(tabStops count: Int) {
        var column = cursor.column
        for _ in 0 ..< min(count, columns) {
            column = tabStops[..<column].lastIndex(of: true) ?? 0
        }
        moveCursor(row: cursor.row, column: column)
    }

    private mutating func clearTabStops(_ mode: Int) {
        switch mode {
        case 0:
            tabStops[cursor.column] = false
        case 3:
            tabStops = Array(repeating: false, count: columns)
        default:
            break
        }
    }

    private static func defaultTabStops(_ columns: Range<Int>) -> [Bool] {
        columns.map { $0 % tabWidth == 0 }
    }

    private mutating func setPrivateMode(_ mode: Int, isEnabled: Bool) {
        switch (mode, isEnabled) {
        case (1, _):
            usesApplicationCursorKeys = isEnabled
        case (7, _):
            usesAutowrap = isEnabled
        case (25, _):
            isCursorVisible = isEnabled
        case (1000, true):
            mouseTracking = .clicks
        case (1002, true), (1003, true):
            mouseTracking = .drags
        case (1000, false), (1002, false), (1003, false):
            mouseTracking = .off
        case (1006, _):
            usesSGRMouseEncoding = isEnabled
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
        savedCursor = SavedCursor(
            position: cursor,
            style: style,
            isWrapPending: isWrapPending,
            usesLineDrawing: usesLineDrawing
        )
    }

    private mutating func restoreCursor() {
        moveCursor(row: savedCursor.position.row, column: savedCursor.position.column)
        style = savedCursor.style
        isWrapPending = savedCursor.isWrapPending
        usesLineDrawing = savedCursor.usesLineDrawing
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
        case 3:
            removedScrollbackCount += scrollback.count
            scrollback.removeAll()
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
        if range.upperBound == columns {
            screen[row].isWrapped = false
        }
        if range.lowerBound == 0 {
            unwrapLine(before: row)
        }
        blankBrokenWideCharacter(at: range.lowerBound, row: row)
        blankBrokenWideCharacter(at: range.upperBound, row: row)
    }

    private var blank: Cell {
        Cell(style: Style(background: style.background))
    }

    private func blankLines(_ count: Int) -> [Line] {
        Array(repeating: Line(repeatElement(blank, count: columns)), count: count)
    }

    private static func resized(_ screen: [Line], columns: Int, rows: Int, removingFirst removedRows: Int)
        -> [Line]
    {
        let lines = screen.dropFirst(removedRows).prefix(rows)
            .map { line in
                var line = Line(line.prefix(columns)) + blankLine(columns: max(columns - line.count, 0))
                if line[columns - 1].width == 2 {
                    line[columns - 1] = Cell()
                }
                return line
            }
        return lines + Array(repeating: blankLine(columns: columns), count: rows - lines.count)
    }

    private static func blankLine(columns: Int) -> Line {
        Line(repeatElement(Cell(), count: columns))
    }
}
