import Foundation

package struct Terminal: Sendable {
    package struct Position: Equatable, Sendable {
        package var row: Int
        package var column: Int

        package init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    package struct WindowReport: Equatable, Sendable {
        package var isVisible = false
        package var x = 0
        package var y = 0
        package var width = 0
        package var height = 0

        package init(isVisible: Bool = false, x: Int = 0, y: Int = 0, width: Int = 0, height: Int = 0) {
            self.isVisible = isVisible
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    package struct RGB: Equatable, Sendable {
        package var red: UInt16
        package var green: UInt16
        package var blue: UInt16

        package init(red: UInt16, green: UInt16, blue: UInt16) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    private struct SavedCursor {
        var position = Position(row: 0, column: 0)
        var style = Style()
        var characterSets: [Unicode.Scalar] = ["B", "B", "B", "B"]
        var usesOriginMode = false
    }

    private static let maximumBytesPerCell = 1_024
    private static let maximumRepeatCount = 1_000_000

    package private(set) var columns: Int
    package private(set) var rows: Int
    package private(set) var screen: [Line]
    package private(set) var scrollback: Scrollback
    package private(set) var removedScrollbackCount = 0
    package private(set) var cursor = Position(row: 0, column: 0)
    package private(set) var usesApplicationCursorKeys = false
    package private(set) var usesApplicationKeypad = false
    package private(set) var usesBracketedPaste = false
    package private(set) var isCursorVisible = true
    package private(set) var cursorShape = CursorShape.block
    package private(set) var usesFocusReporting = false
    package private(set) var usesReverseVideo = false
    package private(set) var title = ""
    package internal(set) var graphemes = Graphemes()
    package private(set) var bellCount = 0
    package internal(set) var currentDirectory: URL?
    package private(set) var mouseTracking = MouseTracking.off
    package var defaultColors: DefaultColors?
    package internal(set) var changedColors = ChangedColors()
    package var windowReport = WindowReport()
    package private(set) var usesSGRMouseEncoding = false
    package private(set) var usesUTF8MouseEncoding = false
    package private(set) var usesURXVTMouseEncoding = false
    package private(set) var modifyOtherKeys = 0

    package var normalScreenLines: [Line] {
        normalScreen?.lines ?? []
    }

    package var isAlternateScreenActive: Bool {
        normalScreen != nil
    }

    private var usesAutowrap = true
    private var usesOriginMode = false
    private var usesInsertMode = false
    private var usesNewLineMode = false

    private var decoder = UTF8Decoder()
    private var parser = EscapeSequenceParser()
    private var isWrapPending = false
    private var isTextRunClipped = false
    private var isLastCharacterDropped = false
    private var style = Style()
    private var characterSets: [Unicode.Scalar] = ["B", "B", "B", "B"]
    private var activeCharacterSet = 0
    private var lastCharacter: Unicode.Scalar? = " "
    private var savedCursor = SavedCursor()
    private var scrollRegion: Range<Int>
    private var hasScrollRegion = false
    private var hasMovedCursorForFullRow = false
    private var tabStops = TabStops()
    var replies: [UInt8] = []
    private var normalScreen: (lines: [Line], cursor: Position, savedCursor: SavedCursor)?
    private var alternateScreen: (lines: [Line], savedCursor: SavedCursor)?

    package init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        screen = Array(repeating: Self.blankLine(columns: columns), count: rows)
        scrollback = Scrollback(columns: columns)
        scrollRegion = 0 ..< rows
    }

    package mutating func resize(columns: Int, rows: Int) {
        resize(columns: columns, rows: rows, restoredRows: rows + 1)
    }

    mutating func resize(columns: Int, rows: Int, restoredRows: Int) {
        precondition(columns > 0 && rows > 0)
        isTextRunClipped = false
        isLastCharacterDropped = false
        let rowChange = rows - self.rows
        if var normalScreen {
            normalScreen.lines =
                relaidScreen(
                    normalScreen.lines,
                    usedRows: normalScreen.lines.count,
                    cursor: nil,
                    columns: columns,
                    rows: rows,
                    restoredRows: restoredRows
                )
                .screen
            normalScreen.savedCursor.position.row += rowChange
            self.normalScreen = normalScreen
            screen = Self.resizedAlternateScreen(screen, columns: columns, rows: rows)
            cursor = Position(row: min(cursor.row, rows - 1), column: min(cursor.column, columns - 1))
        } else {
            let usedRows =
                !scrollback.isEmpty || cursor.row == self.rows - 1
                ? self.rows : (screen.lastIndex { $0.contains(where: \.isWritten) } ?? -1) + 1
            (screen, cursor) = relaidScreen(
                screen, usedRows: usedRows, cursor: cursor, columns: columns, rows: rows, restoredRows: restoredRows)
        }
        if var alternateScreen {
            alternateScreen.lines = Self.resizedAlternateScreen(alternateScreen.lines, columns: columns, rows: rows)
            alternateScreen.savedCursor.position.row += rowChange
            self.alternateScreen = alternateScreen
        }
        savedCursor.position.row += rowChange
        self.columns = columns
        self.rows = rows
        if !hasScrollRegion {
            scrollRegion = 0 ..< rows
        }
    }

    private mutating func relaidScreen(
        _ screen: [Line],
        usedRows: Int,
        cursor: Position?,
        columns: Int,
        rows: Int,
        restoredRows: Int
    ) -> (screen: [Line], cursor: Position) {
        let restored = scrollback.removeLast(coveringRows: restoredRows, columns: columns)
        scrollback.relayOut(columns: columns)
        let storedCursor = cursor.flatMap {
            $0.row < usedRows ? Position(row: restored.count + $0.row, column: $0.column) : nil
        }
        var (lines, target) = Self.reflow(restored + screen.prefix(usedRows), columns: columns, cursor: storedCursor)
        var column = target?.column ?? 0
        if let cursor, usedRows == self.rows, (lines.last?.textCount ?? 0) >= columns {
            if cursor.row == self.rows - 1 || hasMovedCursorForFullRow {
                lines[lines.count - 1].isWrapped = true
                lines.append(Line())
                hasMovedCursorForFullRow = false
            } else {
                column += 1
                hasMovedCursorForFullRow = true
            }
        } else {
            hasMovedCursorForFullRow = false
        }
        var top = max(lines.count - rows, 0)
        var row = 0
        if let cursor {
            row = target?.row ?? lines.count + cursor.row - usedRows + (cursor.column > 0 ? 1 : 0)
            if target == nil {
                top = max(top, min(row - rows + 1, lines.count - usedRows + self.rows - 2 * rows))
                lines += Array(repeating: Line(), count: max(top - lines.count, 0))
            }
        }
        keepInScrollback(lines[..<top])
        var newScreen = lines[top...].map { Self.padded($0, columns: columns) }
        guard cursor != nil else {
            return (newScreen, Position(row: 0, column: 0))
        }
        newScreen += Array(repeating: Self.blankLine(columns: columns), count: rows - newScreen.count)
        if row < top {
            row = top + rows - 1
        } else if row >= top + rows {
            row = top + rows - 1
            column = newScreen[rows - 1].textCount + 1
        }
        return (newScreen, Position(row: row - top, column: min(column, columns - 1)))
    }

    private static func resizedAlternateScreen(_ screen: [Line], columns: Int, rows: Int) -> [Line] {
        let lines =
            rows < screen.count
            ? Array(screen.suffix(rows))
            : Array(repeating: blankLine(columns: columns), count: rows - screen.count) + screen
        return lines.map { padded($0, columns: columns) }
    }

    package mutating func receive(_ bytes: [UInt8]) -> [UInt8] {
        defer { replies.removeAll() }
        for scalar in decoder.decode(bytes) {
            guard let action = parser.advance(scalar) else {
                continue
            }
            if case .print = action {
            } else {
                isTextRunClipped = false
                isLastCharacterDropped = false
            }
            switch action {
            case .print(let scalar):
                let characterSet = characterSets[activeCharacterSet]
                let printed = characterSet == "B" ? scalar : Self.translated(scalar, byCharacterSet: characterSet)
                lastCharacter = scalar.isASCII ? (printed == scalar ? scalar : " ") : nil
                print(printed)
            case .execute("\n"), .execute("\u{B}"), .execute("\u{C}"):
                lineFeed()
                if usesNewLineMode {
                    carriageReturn()
                }
            case .execute("\r"):
                carriageReturn()
            case .execute("\u{7}"):
                bellCount += 1
            case .execute("\u{8}"):
                moveBackward(1)
            case .execute("\t"):
                moveToNextTabStop()
            case .escape(intermediates: "", final: "D"):
                lineFeed()
            case .escape(intermediates: "", final: "E"):
                carriageReturn()
                lineFeed()
            case .escape(intermediates: "", final: "c"):
                reset()
            case .escape(intermediates: "", final: "H"):
                tabStops.set(true, at: cursor.column)
            case .escape(intermediates: "", final: "M"):
                reverseLineFeed()
            case .execute("\u{E}"):
                activeCharacterSet = 1
            case .execute("\u{F}"):
                activeCharacterSet = 0
            case .escape(intermediates: "", final: "n"):
                activeCharacterSet = 2
            case .escape(intermediates: "", final: "o"):
                activeCharacterSet = 3
            case .escape(intermediates: "(", let final):
                characterSets[0] = final
            case .escape(intermediates: ")", let final), .escape(intermediates: "-", let final):
                characterSets[1] = final
            case .escape(intermediates: "*", let final), .escape(intermediates: ".", let final):
                characterSets[2] = final
            case .escape(intermediates: "+", let final), .escape(intermediates: "/", let final):
                characterSets[3] = final
            case .escape(intermediates: "#", final: "8"):
                fillScreen()
            case .escape(intermediates: "", final: "="):
                usesApplicationKeypad = true
            case .escape(intermediates: "", final: ">"):
                usesApplicationKeypad = false
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
            if case .print = action {
            } else {
                isTextRunClipped = false
                isLastCharacterDropped = false
            }
        }
        return replies
    }

    package mutating func clearToStart() {
        keepInScrollback(screen.prefix(cursor.row))
        scrollUp(cursor.row, in: 0 ..< rows)
        cursor.row = 0
        eraseInDisplay(3)
    }

    package mutating func completeProcess() {
        moveToNextScreenRow()
        let text = "[Process completed]".unicodeScalars
            .map { $0 == " " ? .writtenSpace() : Cell(scalar: $0) }
        screen[cursor.row].insert(contentsOf: text, at: 0)
        moveToNextScreenRow()
    }

    private mutating func moveToNextScreenRow() {
        carriageReturn()
        guard cursor.row == rows - 1 else {
            cursor.row += 1
            return
        }
        if normalScreen == nil {
            keepInScrollback(screen.prefix(1))
        }
        scrollUp(1, in: 0 ..< rows)
    }

    private mutating func perform(_ sequence: EscapeSequenceParser.ControlSequence) {
        if sequence.privateMarker == nil, sequence.intermediates == " ", sequence.final == "q" {
            setCursorShape(sequence.parameter(at: 0, default: 0))
            return
        }
        if sequence.privateMarker == nil, sequence.intermediates == "!", sequence.final == "p" {
            softReset()
            return
        }
        guard sequence.intermediates.isEmpty else {
            return
        }
        if sequence.privateMarker == "?", sequence.final == "h" || sequence.final == "l" {
            for mode in sequence.parameters {
                setPrivateMode(mode, isEnabled: sequence.final == "h")
            }
            return
        }
        if sequence.privateMarker == ">", sequence.final == "c" {
            if sequence.parameters.count <= 1, sequence.parameter(at: 0, default: 0) == 0 {
                replies += "\u{1B}[>1;95;0c".utf8
            }
            return
        }
        if sequence.privateMarker == ">",
            sequence.final == "m" && [nil, 4].contains(sequence.parameters.first)
                || sequence.final == "n" && sequence.parameters.first == 4
        {
            let level = sequence.final == "m" ? sequence.parameter(at: 1, default: 0) : 0
            modifyOtherKeys = level <= 2 ? level : 0
            return
        }
        guard sequence.privateMarker == nil else {
            return
        }
        let count = sequence.parameter(at: 0, default: 1)
        switch sequence.final {
        case "A":
            moveCursor(row: max(cursor.row - count, topLimit), column: cursor.column)
        case "B":
            moveCursor(row: min(cursor.row + count, bottomLimit), column: cursor.column)
        case "C":
            moveCursor(row: cursor.row, column: cursor.column + count)
        case "D":
            if isWrapPending {
                moveBackwardFromWrap(count)
            } else {
                moveBackward(count)
            }
        case "E":
            moveCursor(row: min(cursor.row + count, bottomLimit), column: 0)
        case "F":
            moveCursor(row: max(cursor.row - count, topLimit), column: 0)
        case "G", "`":
            moveCursor(row: cursor.row, column: count - 1)
        case "I":
            moveForward(tabStops: count)
        case "Z":
            moveBackward(tabStops: count)
        case "g":
            clearTabStops(sequence.parameter(at: 0, default: 0))
        case "H", "f":
            moveCursor(row: min(topLimit + count - 1, bottomLimit), column: sequence.parameter(at: 1, default: 1) - 1)
        case "d":
            cursor.row = min(topLimit + count - 1, bottomLimit, rows - 1)
        case "J":
            eraseInDisplay(sequence.parameter(at: 0, default: 0))
        case "K":
            eraseInLine(sequence.parameter(at: 0, default: 0))
        case "@":
            insertCharacters(count)
        case "b":
            if let lastCharacter {
                isWrapPending = false
                for _ in 0 ..< min(count, Self.maximumRepeatCount) {
                    place(lastCharacter)
                }
            }
        case "P":
            deleteCharacters(count)
        case "X":
            erase(cursor.column ..< min(cursor.column + count, columns), row: cursor.row, with: writtenBlank)
        case "L":
            insertLines(count)
        case "M":
            deleteLines(count)
        case "S":
            scrollRegionUp(count)
        case "T":
            scrollDown(count, in: scrollRegion.clamped(to: 0 ..< rows))
        case "c" where sequence.parameters.count <= 1 && sequence.parameter(at: 0, default: 0) == 0:
            replies += "\u{1B}[?1;2c".utf8
        case "h", "l":
            for mode in sequence.parameters {
                if mode == 4 {
                    usesInsertMode = sequence.final == "h"
                } else if mode == 20 {
                    usesNewLineMode = sequence.final == "h"
                }
            }
        case "m":
            style.apply(sequence.parameters)
        case "n":
            reportStatus(sequence.parameter(at: 0, default: 0))
        case "r":
            setScrollRegion(top: count - 1, bottom: min(sequence.parameter(at: 1, default: rows), rows))
        case "t":
            reportWindow(sequence.parameter(at: 0, default: 0))
        case "x":
            reportTerminalParameters(sequence.parameter(at: 0, default: 0))
        default:
            break
        }
    }

    private mutating func print(_ scalar: Unicode.Scalar) {
        let width = scalar.width
        if width == 0 {
            combine(scalar)
        } else {
            place(scalar, width: width)
        }
    }

    private mutating func place(_ scalar: Unicode.Scalar, width: Int = 1) {
        guard scalar != " " else {
            place(.writtenSpace(style: style))
            return
        }
        place(Cell(scalar: scalar, style: style, width: columns > 1 ? UInt8(width) : 1))
    }

    private mutating func place(_ cell: Cell) {
        let width = Int(cell.width)
        if !usesAutowrap {
            guard !isTextRunClipped, cursor.column + width <= columns else {
                isTextRunClipped = true
                isLastCharacterDropped = true
                return
            }
            isWrapPending = false
        } else if isWrapPending || cursor.column + width > columns {
            let row = cursor.row
            let scrolls = row == scrollRegion.upperBound - 1
            if !isWrapPending, screen[row][columns - 1] == Cell() {
                screen[row][columns - 1] = .padding
            }
            screen[row].isWrapped = true
            carriageReturn()
            lineFeed()
            if scrolls, cursor.row > 0 {
                screen[cursor.row - 1].isWrapped = true
            } else if !scrolls, cursor.row == row {
                screen[row].isWrapped = false
            }
        }
        if usesInsertMode {
            insertCharacters(width)
        }
        for column in cursor.column ..< cursor.column + width {
            clearWideCharacter(at: column)
        }
        screen[cursor.row][cursor.column] = cell
        if width == 2 {
            screen[cursor.row][cursor.column + 1] = Cell(style: cell.style, width: 0)
        }
        if cursor.column + width == columns {
            cursor.column = columns - 1
            isWrapPending = usesAutowrap
            isTextRunClipped = !usesAutowrap
        } else {
            cursor.column += width
        }
    }

    private mutating func clearWideCharacter(at column: Int) {
        breakTab(at: column, row: cursor.row)
        switch screen[cursor.row][column].width {
        case 0 where column > 0:
            screen[cursor.row][column - 1] = writtenBlank
        case 2 where column + 1 < screen[cursor.row].count:
            screen[cursor.row][column + 1] = writtenBlank
        default:
            break
        }
    }

    private mutating func combine(_ scalar: Unicode.Scalar) {
        guard !isLastCharacterDropped else {
            return
        }
        var column = isWrapPending || isTextRunClipped ? cursor.column : cursor.column - 1
        if column > 0, screen[cursor.row][column].width == 0 {
            column -= 1
        }
        guard column >= 0 else {
            return
        }
        let target = screen[cursor.row][column]
        if target.isTab || target.isTabGap {
            guard column + 1 < columns, screen[cursor.row][column + 1].isTabGap else {
                if target.isTabGap {
                    screen[cursor.row][column] = Cell(scalar: scalar, style: target.style)
                }
                return
            }
            breakTab(at: column, row: cursor.row)
        }
        var text = graphemes.character(of: screen[cursor.row][column])
        guard text.utf8.count + UTF8.width(scalar) <= Self.maximumBytesPerCell else {
            return
        }
        text.unicodeScalars.append(scalar)
        screen[cursor.row][column] = graphemes.cell(screen[cursor.row][column], with: text)
    }

    package func character(of cell: Cell) -> String {
        graphemes.character(of: cell)
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
        let count = min(count, columns - cursor.column)
        if screen[cursor.row][cursor.column].isTabGap {
            breakTab(at: cursor.column, row: cursor.row)
        }
        if screen[cursor.row][columns - count].isTabGap {
            breakTab(at: columns - count, row: cursor.row)
        }
        screen[cursor.row].insert(contentsOf: repeatElement(writtenBlank, count: count), at: cursor.column)
        screen[cursor.row].removeLast(screen[cursor.row].count - columns)
        for column in [cursor.column, cursor.column + count, columns] {
            blankBrokenWideCharacter(at: column, row: cursor.row)
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        let count = min(count, columns - cursor.column)
        breakTab(at: cursor.column, row: cursor.row)
        breakTab(at: cursor.column + count - 1, row: cursor.row)
        screen[cursor.row].removeSubrange(cursor.column ..< cursor.column + count)
        screen[cursor.row].isWrapped = false
        screen[cursor.row].append(contentsOf: repeatElement(blank, count: max(columns - screen[cursor.row].count, 0)))
        blankBrokenWideCharacter(at: cursor.column, row: cursor.row)
    }

    private mutating func blankBrokenWideCharacter(at column: Int, row: Int) {
        let count = screen[row].count
        if column > 0, screen[row][column - 1].width == 2, column == count || screen[row][column].width != 0 {
            screen[row][column - 1] = writtenBlank
        }
        if column < count, screen[row][column].width == 0, column == 0 || screen[row][column - 1].width != 2 {
            screen[row][column] = writtenBlank
        }
    }

    private mutating func insertLines(_ count: Int) {
        guard scrollRegion.contains(cursor.row) else {
            return
        }
        scrollDown(count, in: cursor.row ..< min(scrollRegion.upperBound, rows))
    }

    private mutating func deleteLines(_ count: Int) {
        guard scrollRegion.contains(cursor.row) else {
            return
        }
        if cursor.row == 0 {
            scrollRegionUp(count)
            return
        }
        scrollUp(count, in: cursor.row ..< min(scrollRegion.upperBound, rows))
        unwrapLine(before: cursor.row)
    }

    private mutating func setScrollRegion(top: Int, bottom: Int) {
        guard top < bottom - 1 else {
            return
        }
        scrollRegion = top ..< bottom
        hasScrollRegion = top > 0 || bottom < rows
        moveCursor(row: topLimit, column: 0)
    }

    private mutating func keepInScrollback(_ lines: ArraySlice<Line>) {
        var previousLine: Line?
        var keptLine = Line()
        for line in lines {
            if line != previousLine {
                keptLine = Self.trimmed(line)
                previousLine = line
            }
            scrollback.append(keptLine)
        }
    }

    private mutating func scrollRegionUp(_ count: Int) {
        let region = scrollRegion.clamped(to: 0 ..< rows)
        if region.lowerBound == 0, normalScreen == nil {
            keepInScrollback(screen.prefix(min(count, region.count)))
        }
        scrollUp(count, in: region)
    }

    private mutating func scrollUp(_ count: Int, in region: Range<Int>) {
        guard !region.isEmpty else {
            return
        }
        let count = min(count, region.count)
        screen.removeSubrange(region.lowerBound ..< region.lowerBound + count)
        screen.insert(contentsOf: blankLines(count), at: region.upperBound - count)
        if region.lowerBound > 0 {
            unwrapLine(before: region.lowerBound)
        }
        if region.upperBound < rows {
            unwrapLine(before: region.upperBound - count)
        }
    }

    private mutating func scrollDown(_ count: Int, in region: Range<Int>) {
        guard !region.isEmpty else {
            return
        }
        let count = min(count, region.count)
        screen.removeSubrange(region.upperBound - count ..< region.upperBound)
        screen.insert(contentsOf: blankLines(count), at: region.lowerBound)
        unwrapLine(before: region.lowerBound)
        unwrapLine(before: region.upperBound)
    }

    private mutating func unwrapLine(before row: Int) {
        if row > 0 {
            screen[row - 1].isWrapped = false
        } else if normalScreen == nil {
            scrollback.unwrapLastRow()
        }
    }

    private mutating func reverseLineFeed() {
        isWrapPending = false
        if cursor.row == scrollRegion.lowerBound {
            scrollDown(1, in: scrollRegion.clamped(to: 0 ..< rows))
        } else {
            cursor.row = cursor.row == 0 ? rows - 1 : cursor.row - 1
        }
    }

    private var topLimit: Int {
        usesOriginMode ? scrollRegion.lowerBound : 0
    }

    private var bottomLimit: Int {
        usesOriginMode ? min(scrollRegion.upperBound, rows) - 1 : rows - 1
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
        let separator = command.unicodeScalars.firstIndex(of: ";")
        let text = separator.map { command[command.unicodeScalars.index(after: $0)...] }
        let number = Int(command[..<(separator ?? command.endIndex)]).flatMap { $0 <= Int32.max ? $0 : nil } ?? 0
        switch (number, text) {
        case (0, let text?), (2, let text?):
            title = String(text)
        case (7, let text?):
            setCurrentDirectory(text)
        case (4, let text?):
            changeIndexedColors(text)
        case (5, let text?):
            changeSpecialColors(text)
        case (10 ... 19, let text?):
            changeDynamicColors(text, from: number)
        case (104, _):
            resetIndexedColors(text)
        case (105, let text?):
            resetSpecialColors(text)
        case (110, _), (111, _), (112, _), (117, _):
            if text?.isEmpty != false {
                resetDynamicColor(number - 100)
            }
        default:
            break
        }
    }

    private mutating func reset() {
        var terminal = Terminal(columns: columns, rows: rows)
        terminal.title = title
        terminal.bellCount = bellCount
        terminal.defaultColors = defaultColors
        terminal.changedColors = changedColors
        terminal.changedColors.indexed = [:]
        terminal.windowReport = windowReport
        terminal.graphemes = graphemes
        terminal.scrollback = scrollback
        scrollback = Scrollback(columns: columns)
        terminal.unwrapLine(before: 0)
        terminal.removedScrollbackCount = removedScrollbackCount
        terminal.decoder = decoder
        terminal.replies = replies
        terminal.isWrapPending = isWrapPending
        terminal.usesAutowrap = usesAutowrap
        self = terminal
    }

    private mutating func fillScreen() {
        for row in screen.indices {
            screen[row].replaceSubrange(0 ..< columns, with: repeatElement(Cell(scalar: "E"), count: columns))
            blankBrokenWideCharacter(at: columns, row: row)
        }
        unwrapLine(before: 0)
    }

    private mutating func softReset() {
        changedColors.indexed = [:]
        usesInsertMode = false
        usesNewLineMode = false
        usesApplicationCursorKeys = false
        usesApplicationKeypad = false
        usesOriginMode = false
        usesReverseVideo = false
        tabStops = TabStops()
        isCursorVisible = true
        cursorShape = .block
        scrollRegion = 0 ..< rows
        hasScrollRegion = false
        style = Style()
        characterSets = ["B", "B", "B", "B"]
        activeCharacterSet = 0
        lastCharacter = " "
        savedCursor = SavedCursor()
        modifyOtherKeys = 0
    }

    private mutating func moveToNextTabStop() {
        let start = cursor.column
        moveForward(tabStops: 1)
        guard start < cursor.column,
            screen[cursor.row][start ..< cursor.column].allSatisfy({ !$0.isWritten && !$0.isTabGap && $0.width == 1 })
        else {
            return
        }
        screen[cursor.row][start] = .tab(style: screen[cursor.row][start].style)
        for column in start + 1 ..< cursor.column {
            screen[cursor.row][column] = .tabGap(style: screen[cursor.row][column].style)
        }
    }

    private mutating func breakTab(at column: Int, row: Int) {
        guard screen[row][column].isTab || screen[row][column].isTabGap else {
            return
        }
        var start = column
        while start > 0, screen[row][start].isTabGap {
            start -= 1
        }
        if !screen[row][start].isTab {
            start += 1
        }
        var end = column + 1
        while end < screen[row].count, screen[row][end].isTabGap {
            end += 1
        }
        for index in start ..< end {
            screen[row][index] = .writtenSpace(style: screen[row][index].style)
        }
    }

    private mutating func moveForward(tabStops count: Int) {
        isWrapPending = false
        for _ in 0 ..< min(count, columns) {
            cursor.column = (cursor.column + 1 ..< columns).first(where: tabStops.contains) ?? columns - 1
        }
    }

    private mutating func moveBackward(_ count: Int) {
        var row = cursor.row
        var column = cursor.column - count
        while column < 0, row > 0, screen[row - 1].isWrapped {
            row -= 1
            column += columns
        }
        if column < 0, row == 0, normalScreen == nil, scrollback.isLastRowWrapped {
            column += columns
        }
        moveCursor(row: row, column: column)
    }

    private mutating func moveBackwardFromWrap(_ count: Int) {
        guard cursor.column == columns - 1 else {
            moveCursor(row: cursor.row, column: 1)
            return
        }
        let rowCount = count / columns
        var row = cursor.row
        for _ in 0 ..< min(rowCount, rows) {
            guard row > 0, screen[row - 1].isWrapped else {
                break
            }
            row -= 1
        }
        moveCursor(row: row, column: columns - 1 - max(count - 1 - rowCount * columns, 0))
    }

    private mutating func moveBackward(tabStops count: Int) {
        var column = cursor.column
        for _ in 0 ..< min(count, columns) {
            column = (0 ..< column).last(where: tabStops.contains) ?? 0
        }
        moveCursor(row: cursor.row, column: column)
    }

    private mutating func clearTabStops(_ mode: Int) {
        switch mode {
        case 0:
            tabStops.set(false, at: cursor.column)
        case 3:
            tabStops.removeAll()
        default:
            break
        }
    }

    private mutating func setCursorShape(_ shape: Int) {
        switch shape {
        case 0 ... 2:
            cursorShape = .block
        case 3, 4:
            cursorShape = .underline
        case 5, 6:
            cursorShape = .bar
        default:
            break
        }
    }

    private mutating func setPrivateMode(_ mode: Int, isEnabled: Bool) {
        switch (mode, isEnabled) {
        case (1, _):
            usesApplicationCursorKeys = isEnabled
        case (5, _):
            usesReverseVideo = isEnabled
        case (6, _):
            usesOriginMode = isEnabled
            if isEnabled {
                moveCursor(row: topLimit, column: 0)
            }
        case (7, _):
            usesAutowrap = isEnabled
        case (25, _):
            isCursorVisible = isEnabled
        case (1000, true):
            mouseTracking = .clicks
        case (1002, true):
            mouseTracking = .drags
        case (1003, true):
            mouseTracking = .anyMotion
        case (1000, false), (1002, false), (1003, false):
            mouseTracking = .off
        case (1004, _):
            usesFocusReporting = isEnabled
        case (1005, _):
            usesUTF8MouseEncoding = isEnabled
        case (1006, _):
            usesSGRMouseEncoding = isEnabled
        case (1015, _):
            usesURXVTMouseEncoding = isEnabled
        case (2004, _):
            usesBracketedPaste = isEnabled
        case (47, true):
            enterAlternateScreen()
            homeCursor()
        case (47, false):
            if let position = normalScreen?.cursor {
                exitAlternateScreen()
                moveCursor(row: position.row, column: position.column)
            }
        case (1049, true):
            saveCursor()
            enterAlternateScreen()
            screen = blankLines(rows)
            homeCursor()
        case (1049, false):
            exitAlternateScreen()
            restoreCursor()
        default:
            break
        }
    }

    private mutating func homeCursor() {
        cursor = Position(row: min(topLimit, rows - 1), column: 0)
    }

    private mutating func enterAlternateScreen() {
        guard normalScreen == nil else {
            return
        }
        normalScreen = (screen, cursor, savedCursor)
        screen = Array(repeating: Self.blankLine(columns: columns), count: rows)
        if let alternateScreen {
            screen = alternateScreen.lines
        }
        savedCursor = alternateScreen?.savedCursor ?? SavedCursor()
    }

    private mutating func exitAlternateScreen() {
        guard let normalScreen else {
            return
        }
        alternateScreen = (screen, savedCursor)
        screen =
            normalScreen.lines
            + Array(repeating: Self.blankLine(columns: columns), count: rows - normalScreen.lines.count)
        savedCursor = normalScreen.savedCursor
        self.normalScreen = nil
    }

    private mutating func reportStatus(_ request: Int) {
        switch request {
        case 5:
            replies += "\u{1B}[0n".utf8
        case 6:
            replies += "\u{1B}[\(UInt(bitPattern: cursor.row - topLimit + 1));\(cursor.column + 1)R".utf8
        default:
            break
        }
    }

    private mutating func reportWindow(_ request: Int) {
        switch request {
        case 11:
            replies += "\u{1B}[\(windowReport.isVisible ? 1 : 2)t".utf8
        case 13:
            replies += "\u{1B}[3;\(windowReport.x);\(windowReport.y)t".utf8
        case 14:
            replies += "\u{1B}[4;\(windowReport.height);\(windowReport.width)t".utf8
        case 18:
            replies += "\u{1B}[8;\(rows);\(columns)t".utf8
        default:
            break
        }
    }

    private mutating func reportTerminalParameters(_ request: Int) {
        if request <= 1 {
            replies += "\u{1B}[\(request + 2);1;1;112;112;1;0x".utf8
        }
    }

    private mutating func saveCursor() {
        savedCursor = SavedCursor(
            position: Position(row: cursor.row - topLimit, column: cursor.column),
            style: style,
            characterSets: characterSets,
            usesOriginMode: usesOriginMode
        )
    }

    private mutating func restoreCursor() {
        usesOriginMode = savedCursor.usesOriginMode
        moveCursor(row: min(topLimit + savedCursor.position.row, bottomLimit), column: savedCursor.position.column)
        style = savedCursor.style
        characterSets = savedCursor.characterSets
    }

    private mutating func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            if cursor.column == 0 {
                unwrapLine(before: cursor.row)
            }
            eraseInLine(0)
            screen.replaceSubrange(cursor.row + 1 ..< rows, with: blankLines(rows - cursor.row - 1))
        case 1:
            unwrapLine(before: 0)
            screen.replaceSubrange(0 ..< cursor.row, with: blankLines(cursor.row))
            eraseInLine(1)
        case 2:
            if normalScreen == nil {
                keepInScrollback(screen[...])
            }
            unwrapLine(before: 0)
            screen = blankLines(rows)
        case 3:
            normalScreen?.lines = Array(repeating: Self.blankLine(columns: columns), count: rows)
            removedScrollbackCount += scrollback.count
            scrollback.removeAll()
        default:
            break
        }
    }

    private mutating func eraseInLine(_ mode: Int) {
        switch mode {
        case 0:
            removeCells(cursor.column ..< columns)
        case 1:
            erase(0 ..< cursor.column + 1, row: cursor.row, with: writtenBlank)
        case 2:
            removeCells(0 ..< columns)
        default:
            break
        }
    }

    private mutating func removeCells(_ range: Range<Int>) {
        let overflow = screen[cursor.row].count - columns
        guard overflow > 0 else {
            erase(range, row: cursor.row, with: blank)
            return
        }
        breakTab(at: range.lowerBound, row: cursor.row)
        breakTab(at: range.upperBound - 1, row: cursor.row)
        screen[cursor.row].removeSubrange(range)
        screen[cursor.row].append(contentsOf: repeatElement(blank, count: max(columns - screen[cursor.row].count, 0)))
        screen[cursor.row].isWrapped = false
        blankBrokenWideCharacter(at: range.lowerBound, row: cursor.row)
    }

    private mutating func erase(_ range: Range<Int>, row: Int, with cell: Cell) {
        breakTab(at: range.lowerBound, row: row)
        breakTab(at: range.upperBound - 1, row: row)
        screen[row].replaceSubrange(range, with: repeatElement(cell, count: range.count))
        if range.upperBound == columns {
            screen[row].isWrapped = false
        }
        blankBrokenWideCharacter(at: range.lowerBound, row: row)
        blankBrokenWideCharacter(at: range.upperBound, row: row)
    }

    private var blank: Cell {
        Cell(style: Style(background: style.background))
    }

    private var writtenBlank: Cell {
        .writtenSpace(style: Style(background: style.background))
    }

    private func blankLines(_ count: Int) -> [Line] {
        Array(repeating: Line(repeatElement(blank, count: columns)), count: count)
    }

    private static func padded(_ line: Line, columns: Int) -> Line {
        guard line.count < columns else {
            return line
        }
        var line = line
        line.append(contentsOf: repeatElement(line.fill ?? Cell(), count: columns - line.count))
        return line
    }

    private static func blankLine(columns: Int) -> Line {
        Line(repeatElement(Cell(), count: columns))
    }
}
