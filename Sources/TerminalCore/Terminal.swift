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
        var usesLineDrawing = false
    }

    private static let maximumBytesPerCell = 1_024
    private static let maximumRepeatCount = 1_000_000
    private static let maximumTitleStackDepth = 10

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
    package internal(set) var programStatus: ProgramStatus?
    package private(set) var mouseTracking = MouseTracking.off
    package var defaultColors: DefaultColors?
    package internal(set) var changedColors = ChangedColors()
    package private(set) var usesSGRMouseEncoding = false
    package private(set) var modifyOtherKeys = 0
    package private(set) var synchronizedOutputCount = 0
    package private(set) var restoredNormalScreenCount = 0

    package var isAlternateScreenActive: Bool {
        normalSavedCursor != nil
    }

    package var isSynchronizingOutput: Bool {
        !synchronizedSnapshot.isEmpty
    }

    package var displayed: Terminal {
        guard var snapshot = synchronizedSnapshot.first else {
            return self
        }
        snapshot.scrollback = scrollback
        snapshot.removedScrollbackCount = removedScrollbackCount
        snapshot.restoredNormalScreenCount = restoredNormalScreenCount
        snapshot.graphemes = graphemes
        return snapshot
    }

    private var usesAutowrap = true
    private var usesInsertMode = false

    private var decoder = UTF8Decoder()
    private var parser = EscapeSequenceParser()
    private var isWrapPending = false
    private var isTextRunClipped = false
    private var isLastCharacterDropped = false
    private var isAfterPrint = false
    private var style = Style()
    private var usesLineDrawing = false
    private var lastCharacter: Unicode.Scalar? = " "
    private var savedCursor = SavedCursor()
    private var scrollRegion: Range<Int>
    private var hasScrollRegion = false
    private var hasMovedCursorForFullRow = false
    private var tabStops = TabStops()
    var replies: [UInt8] = []
    private var normalSavedCursor: SavedCursor?
    private var alternateSavedCursor: SavedCursor?
    private var titleStack: [String] = []
    private var repeatsLeft = 0
    private var synchronizedSnapshot: [Terminal] = []

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
        endSynchronizedOutput()
        isTextRunClipped = false
        isLastCharacterDropped = false
        isAfterPrint = false
        let rowChange = rows - self.rows
        if normalSavedCursor != nil {
            removedScrollbackCount += scrollback.relayOut(columns: columns)
            normalSavedCursor?.position.row += rowChange
            screen = Self.resizedAlternateScreen(screen, columns: columns, rows: rows)
            cursor = Position(row: min(cursor.row, rows - 1), column: min(cursor.column, columns - 1))
        } else {
            let usedRows =
                !scrollback.isEmpty || cursor.row == self.rows - 1
                ? self.rows : (screen.lastIndex { $0.contains(where: \.isWritten) } ?? -1) + 1
            (screen, cursor) = relaidScreen(
                screen, usedRows: usedRows, cursor: cursor, columns: columns, rows: rows, restoredRows: restoredRows)
        }
        alternateSavedCursor?.position.row += rowChange
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
        removedScrollbackCount += scrollback.relayOut(columns: columns)
        let storedCursor = cursor.map { Position(row: restored.count + $0.row, column: $0.column) }
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
                if rows < self.rows, row >= top + rows, top + rows <= lines.count, lines[top + rows - 1].textCount > 0 {
                    row = lines.count + cursor.row - usedRows
                    column = cursor.column
                    top = max(top, row - rows + 1)
                }
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
        repeatsLeft = Self.maximumRepeatCount
        for scalar in decoder.decode(bytes) {
            guard let action = parser.advance(scalar) else {
                continue
            }
            if case .print(let scalar) = action {
                let printed = usesLineDrawing ? Self.lineDrawingCharacter(for: scalar) : scalar
                lastCharacter = scalar.isASCII ? (printed == scalar ? scalar : " ") : nil
                print(printed)
                continue
            }
            isTextRunClipped = false
            isLastCharacterDropped = false
            isAfterPrint = false
            switch action {
            case .execute("\n"), .execute("\u{B}"), .execute("\u{C}"):
                lineFeed()
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
            case .escape(intermediates: "(", final: "0"):
                usesLineDrawing = true
            case .escape(intermediates: "(", final: "B"):
                usesLineDrawing = false
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
            isTextRunClipped = false
            isLastCharacterDropped = false
            isAfterPrint = false
        }
        return replies
    }

    package mutating func endSynchronizedOutput() {
        synchronizedSnapshot = []
    }

    package mutating func clearToStart() {
        keepInScrollback(screen.prefix(cursor.row))
        scrollUp(cursor.row, in: 0 ..< rows)
        cursor.row = 0
        eraseInDisplay(3)
    }

    private mutating func perform(_ sequence: EscapeSequenceParser.ControlSequence) {
        guard sequence.subparameters.isEmpty else {
            return
        }
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
        if sequence.privateMarker == ">", sequence.final == "m" && [nil, 4].contains(sequence.parameters.first) {
            let level = sequence.parameter(at: 1, default: 0)
            modifyOtherKeys = level <= 2 ? level : 0
            return
        }
        if sequence.privateMarker == "?", sequence.final == "m", sequence.parameters.first == 4 {
            replies += "\u{1B}[>4;\(modifyOtherKeys)m".utf8
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
            moveBackward(count)
        case "E":
            moveCursor(row: cursor.row + count, column: 0)
        case "F":
            moveCursor(row: cursor.row - count, column: 0)
        case "G", "`":
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
            cursor.row = min(count - 1, rows - 1)
        case "J":
            eraseInDisplay(sequence.parameter(at: 0, default: 0))
        case "K":
            eraseInLine(sequence.parameter(at: 0, default: 0))
        case "@":
            insertCharacters(count)
        case "b":
            if let lastCharacter {
                isWrapPending = false
                let repeats = min(count, repeatsLeft)
                repeatsLeft -= repeats
                for _ in 0 ..< repeats {
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
            for mode in sequence.parameters where mode == 4 {
                usesInsertMode = sequence.final == "h"
            }
        case "m":
            style.apply(sequence.parameters)
        case "n":
            reportStatus(sequence.parameter(at: 0, default: 0))
        case "r":
            setScrollRegion(top: count - 1, bottom: min(sequence.parameter(at: 1, default: rows), rows))
        case "t" where count == 22 && sequence.parameter(at: 1, default: 0) <= 2:
            let saved = sequence.parameter(at: 1, default: 0) == 1 ? titleStack.last ?? title : title
            titleStack = Array((titleStack + [saved]).suffix(Self.maximumTitleStackDepth))
        case "t" where count == 23 && sequence.parameter(at: 1, default: 0) <= 2:
            if let saved = titleStack.popLast(), sequence.parameter(at: 1, default: 0) != 1 {
                title = saved
            }
        default:
            break
        }
    }

    private mutating func print(_ scalar: Unicode.Scalar) {
        let width = scalar.width
        if width == 0 || isAfterPrint && extendsEmoji(with: scalar) {
            combine(scalar)
        } else {
            place(scalar, width: width)
        }
        isAfterPrint = true
    }

    private static func extendsEmoji(_ character: String, with scalar: Unicode.Scalar) -> Bool {
        guard let base = character.unicodeScalars.first, base.properties.isEmoji else {
            return false
        }
        if isRegionalIndicator(scalar) {
            return isRegionalIndicator(base)
        }
        if scalar == "\u{20E3}" {
            return base.isASCII
        }
        if scalar.properties.isEmojiModifier {
            return base.properties.isEmojiModifierBase
        }
        return !base.isASCII && !isRegionalIndicator(base) && !base.properties.isEmojiModifier
            && (scalar == "\u{200D}" || scalar.properties.isEmoji || ("\u{E0020}" ... "\u{E007F}").contains(scalar))
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        ("\u{1F1E6}" ... "\u{1F1FF}").contains(scalar)
    }

    private static func isWideEmoji(_ character: String) -> Bool {
        let scalars = Array(character.unicodeScalars)
        guard scalars[0].properties.isEmoji else {
            return false
        }
        if isRegionalIndicator(scalars[0]) {
            return isRegionalIndicator(scalars[1])
        }
        return scalars[1] == "\u{FE0F}"
            || scalars[0].properties.isEmojiModifierBase && scalars[1].properties.isEmojiModifier
            || zip(scalars, scalars.dropFirst()).contains { $0 == "\u{200D}" && $1.properties.isEmoji }
    }

    private var combiningColumn: Int? {
        var column = isWrapPending || isTextRunClipped ? cursor.column : cursor.column - 1
        if column > 0, screen[cursor.row][column].width == 0 {
            column -= 1
        }
        return column >= 0 ? column : nil
    }

    private func extendsEmoji(with scalar: Unicode.Scalar) -> Bool {
        guard !scalar.isASCII, !isLastCharacterDropped, let column = combiningColumn else {
            return false
        }
        var text = graphemes.character(of: screen[cursor.row][column])
        guard Self.extendsEmoji(text, with: scalar) else {
            return false
        }
        text.unicodeScalars.append(scalar)
        return text.count == 1
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
        case 2:
            screen[cursor.row][column + 1] = writtenBlank
        default:
            break
        }
    }

    private mutating func combine(_ scalar: Unicode.Scalar) {
        guard !isLastCharacterDropped else {
            return
        }
        guard let column = combiningColumn else {
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
        if isAfterPrint, screen[cursor.row][column].width == 1, Self.isWideEmoji(text) {
            widen(column)
        }
    }

    private mutating func widen(_ column: Int) {
        guard columns > 1 else {
            return
        }
        guard !isWrapPending else {
            var cell = screen[cursor.row][column]
            cell.width = 2
            screen[cursor.row][column] = .padding
            place(cell)
            return
        }
        guard column + 1 < columns else {
            return
        }
        if usesInsertMode {
            insertCharacters(1)
        }
        clearWideCharacter(at: column + 1)
        screen[cursor.row][column].width = 2
        screen[cursor.row][column + 1] = Cell(style: screen[cursor.row][column].style, width: 0)
        if column + 2 == columns {
            isWrapPending = usesAutowrap
            isTextRunClipped = !usesAutowrap
        } else {
            cursor.column += 1
        }
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
        moveCursor(row: 0, column: 0)
    }

    private mutating func keepInScrollback(_ lines: ArraySlice<Line>) {
        var previousLine: Line?
        var keptLine = Line()
        for line in lines {
            if line != previousLine {
                keptLine = Self.trimmed(line)
                previousLine = line
            }
            removedScrollbackCount += scrollback.append(keptLine)
        }
    }

    private mutating func scrollRegionUp(_ count: Int) {
        let region = scrollRegion.clamped(to: 0 ..< rows)
        if region.lowerBound == 0, normalSavedCursor == nil {
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
        } else if normalSavedCursor == nil {
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
        case (10 ... 12, let text?):
            changeDynamicColors(text, from: number)
        case (112, _):
            changedColors.cursor = nil
        case (7501, let text?):
            reportProgramStatus(text)
        default:
            break
        }
    }

    private mutating func reset() {
        exitAlternateScreen()
        var terminal = Terminal(columns: columns, rows: rows)
        terminal.title = title
        terminal.programStatus = programStatus
        terminal.bellCount = bellCount
        terminal.synchronizedOutputCount = synchronizedOutputCount
        terminal.defaultColors = defaultColors
        terminal.changedColors = changedColors
        terminal.changedColors.indexed = [:]
        terminal.graphemes = graphemes
        terminal.scrollback = scrollback
        scrollback = Scrollback(columns: columns)
        terminal.unwrapLine(before: 0)
        terminal.removedScrollbackCount = removedScrollbackCount
        terminal.restoredNormalScreenCount = restoredNormalScreenCount
        terminal.decoder = decoder
        terminal.replies = replies
        terminal.repeatsLeft = repeatsLeft
        terminal.usesAutowrap = usesAutowrap
        self = terminal
    }

    private mutating func softReset() {
        changedColors.indexed = [:]
        usesInsertMode = false
        usesApplicationCursorKeys = false
        usesApplicationKeypad = false
        usesReverseVideo = false
        tabStops = TabStops()
        isCursorVisible = true
        cursorShape = .block
        scrollRegion = 0 ..< rows
        hasScrollRegion = false
        style = Style()
        usesLineDrawing = false
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
        moveCursor(row: cursor.row, column: cursor.column - count)
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
        case (1006, _):
            usesSGRMouseEncoding = isEnabled
        case (2004, _):
            usesBracketedPaste = isEnabled
        case (1049, true):
            saveCursor()
            enterAlternateScreen()
            screen = blankLines(rows)
            cursor = Position(row: 0, column: 0)
        case (1049, false):
            exitAlternateScreen()
            restoreCursor()
        case (2026, true) where synchronizedSnapshot.isEmpty:
            var snapshot = self
            snapshot.scrollback = Scrollback(columns: columns)
            snapshot.graphemes = Graphemes()
            synchronizedSnapshot = [snapshot]
            synchronizedOutputCount += 1
        case (2026, false):
            endSynchronizedOutput()
        default:
            break
        }
    }

    private mutating func enterAlternateScreen() {
        guard normalSavedCursor == nil else {
            return
        }
        keepInScrollback(screen[...])
        normalSavedCursor = savedCursor
        savedCursor = alternateSavedCursor ?? SavedCursor()
    }

    private mutating func exitAlternateScreen() {
        guard let normalSavedCursor else {
            return
        }
        alternateSavedCursor = savedCursor
        let lines =
            Self.reflow(scrollback.removeLast(coveringRows: rows, columns: columns), columns: columns, cursor: nil)
            .lines
        let top = max(lines.count - rows, 0)
        keepInScrollback(lines[..<top])
        screen =
            lines[top...].map { Self.padded($0, columns: columns) }
            + Array(repeating: Self.blankLine(columns: columns), count: rows - lines.count + top)
        savedCursor = normalSavedCursor
        self.normalSavedCursor = nil
        restoredNormalScreenCount += 1
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
            usesLineDrawing: usesLineDrawing
        )
    }

    private mutating func restoreCursor() {
        moveCursor(row: savedCursor.position.row, column: savedCursor.position.column)
        style = savedCursor.style
        usesLineDrawing = savedCursor.usesLineDrawing
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
            if normalSavedCursor == nil {
                keepInScrollback(screen[...])
            }
            unwrapLine(before: 0)
            screen = blankLines(rows)
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
