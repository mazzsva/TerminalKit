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
        var characterSets: [Unicode.Scalar] = ["B", "B", "B", "B"]
        var usesOriginMode = false
    }

    private static let tabWidth = 8
    private static let maximumScalarsPerCell = 16
    private static let maximumScrollback = 10_000
    private static let scrollbackTrimCount = 1_000
    private static let maximumKeyboardFlagsDepth = 8
    private static let maximumRepeatCount = 1_000_000

    package private(set) var columns: Int
    package private(set) var rows: Int
    package private(set) var screen: [Line]
    package private(set) var scrollback: [Line] = []
    package private(set) var removedScrollbackCount = 0
    package private(set) var cursor = Position(row: 0, column: 0)
    package private(set) var usesApplicationCursorKeys = false
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
    package var reportedColors: [RGB] = []
    package private(set) var usesSGRMouseEncoding = false
    package private(set) var modifyOtherKeys = 0

    package var normalScreenLines: [Line] {
        normalScreen?.lines ?? []
    }

    package var isAlternateScreenActive: Bool {
        normalScreen != nil
    }

    package var usesDisambiguatedKeys: Bool {
        keyboardFlagStacks[isAlternateScreenActive ? 1 : 0].last == 1
    }

    private var usesAutowrap = true
    private var usesOriginMode = false
    private var usesInsertMode = false
    private var usesNewLineMode = false

    private var decoder = UTF8Decoder()
    private var parser = EscapeSequenceParser()
    private var isWrapPending = false
    private var isTextRunClipped = false
    private var isAfterPrint = false
    private var style = Style()
    private var characterSets: [Unicode.Scalar] = ["B", "B", "B", "B"]
    private var activeCharacterSet = 0
    private var lastCharacter: Unicode.Scalar? = " "
    private var savedCursor = SavedCursor()
    private var scrollRegion: Range<Int>
    private var tabStops: [Bool]
    private var replies: [UInt8] = []
    private var normalScreen: (lines: [Line], cursor: Position, savedCursor: SavedCursor)?
    private var alternateScreen: (lines: [Line], savedCursor: SavedCursor)?
    private var keyboardFlagStacks: [[Int]] = [[], []]

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
        isTextRunClipped = false
        if columns != self.columns {
            guard var normalScreen else {
                let (lines, anchors) = reflow(
                    screen,
                    keeping: [(cursor, isWrapPending), (savedCursor.position, false)],
                    columns: columns,
                    rows: rows
                )
                screen = lines
                (cursor, isWrapPending) = anchors[0]
                savedCursor.position = anchors[1].position
                setSize(columns: columns, rows: rows)
                return
            }
            let saved = normalScreen.savedCursor
            let (lines, anchors) = reflow(
                normalScreen.lines,
                keeping: [(normalScreen.cursor, false), (saved.position, false)],
                columns: columns,
                rows: rows
            )
            normalScreen.lines = lines
            normalScreen.cursor = anchors[0].position
            normalScreen.savedCursor.position = anchors[1].position
            self.normalScreen = normalScreen
        }
        let removedRows = max(cursor.row + 1 - rows, 0)
        if normalScreen == nil {
            keepInScrollback(screen.prefix(removedRows))
            savedCursor.position.row = min(max(savedCursor.position.row - removedRows, 0), rows - 1)
        }
        screen = Self.resized(screen, columns: columns, rows: rows, removingFirst: removedRows)
        if var normalScreen {
            let removedNormalRows = max(normalScreen.cursor.row + 1 - rows, 0)
            keepInScrollback(normalScreen.lines.prefix(removedNormalRows))
            normalScreen.lines = Self.resized(
                normalScreen.lines,
                columns: columns,
                rows: rows,
                removingFirst: removedNormalRows
            )
            normalScreen.cursor.row -= removedNormalRows
            normalScreen.savedCursor.position.row = min(
                max(normalScreen.savedCursor.position.row - removedNormalRows, 0),
                rows - 1
            )
            self.normalScreen = normalScreen
        }
        let keepsPendingWrap = isWrapPending && columns == self.columns
        setSize(columns: columns, rows: rows)
        moveCursor(row: cursor.row - removedRows, column: cursor.column)
        isWrapPending = keepsPendingWrap
    }

    private mutating func setSize(columns: Int, rows: Int) {
        tabStops =
            columns > self.columns
            ? tabStops + Self.defaultTabStops(self.columns ..< columns) : Array(tabStops.prefix(columns))
        self.columns = columns
        self.rows = rows
        scrollRegion = 0 ..< rows
    }

    private mutating func reflow(
        _ screen: [Line],
        keeping anchors: [(position: Position, isWrapPending: Bool)],
        columns: Int,
        rows: Int
    ) -> (screen: [Line], anchors: [(position: Position, isWrapPending: Bool)]) {
        let oldLines = scrollback + screen
        let positions =
            anchors.map {
                Position(
                    row: scrollback.count + min(max($0.position.row, 0), screen.count - 1),
                    column: min(max($0.position.column, 0), self.columns - 1)
                )
            }
            + [Position(row: scrollback.count, column: 0)]
        var groupStart = positions[0].row
        while groupStart > scrollback.count, oldLines[groupStart - 1].isWrapped {
            groupStart -= 1
        }
        var groupEnd = positions[0].row
        while groupEnd < oldLines.count - 1, oldLines[groupEnd].isWrapped {
            groupEnd += 1
        }
        var lines: [Line] = []
        var mapped = positions
        for (part, reflows) in [
            (0 ..< groupStart, true), (groupStart ..< groupEnd + 1, false), (groupEnd + 1 ..< oldLines.count, true),
        ] {
            let indices = positions.indices.filter { part.contains(positions[$0].row) }
            if reflows {
                let (partLines, partPositions) = Self.reflow(
                    Array(oldLines[part]),
                    columns: columns,
                    positions: indices.map {
                        Position(row: positions[$0].row - part.lowerBound, column: positions[$0].column)
                    }
                )
                for (index, position) in zip(indices, partPositions) {
                    mapped[index] = Position(row: lines.count + position.row, column: position.column)
                }
                lines += partLines
            } else {
                for index in indices {
                    mapped[index] = Position(
                        row: lines.count + positions[index].row - part.lowerBound,
                        column: min(positions[index].column, columns - 1)
                    )
                }
                lines += oldLines[part]
                    .map { line in
                        var line = Self.fitted(line, columns: columns)
                        line.isWrapped = false
                        return line
                    }
            }
        }
        let firstRow = mapped[mapped.count - 1].row
        var newScreen = Array(lines[firstRow...])
        var newScrollback = Array(lines[..<firstRow])
        var newAnchors = zip(anchors, mapped)
            .map { anchor, position in
                let row = position.row - firstRow
                guard anchor.isWrapPending else {
                    return (position: Position(row: row, column: position.column), isWrapPending: false)
                }
                return position.column + 1 < columns
                    ? (Position(row: row, column: position.column + 1), false)
                    : (Position(row: row, column: columns - 1), true)
            }
        let cursorRow = newAnchors.first?.position.row ?? 0
        while newScreen.count > rows, newScreen.count - 1 > cursorRow, let last = newScreen.last, !last.isWrapped,
            last.allSatisfy(\.isBlank)
        {
            newScreen.removeLast()
        }
        let movedRows = min(max(newScreen.count - rows, 0), cursorRow)
        newScrollback += newScreen.prefix(movedRows)
        newScreen = Array(newScreen.dropFirst(movedRows).prefix(rows))
        newScreen += Array(repeating: Line(), count: rows - newScreen.count)
        for index in newAnchors.indices {
            newAnchors[index].position.row = min(max(newAnchors[index].position.row - movedRows, 0), rows - 1)
        }
        scrollback = newScrollback
        trimScrollback()
        let paddedScreen = newScreen.map { line in
            var line = line
            line.append(contentsOf: repeatElement(Cell(), count: columns - line.count))
            return line
        }
        return (paddedScreen, newAnchors)
    }

    package mutating func receive(_ bytes: [UInt8]) -> [UInt8] {
        defer { replies.removeAll() }
        for scalar in decoder.decode(bytes) {
            guard let action = parser.advance(scalar) else {
                continue
            }
            if case .print = action {} else { isTextRunClipped = false }
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
                tabStops[cursor.column] = true
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
            if case .print = action {} else { isTextRunClipped = false }
        }
        return replies
    }

    package mutating func clearToStart() {
        keepInScrollback(screen.prefix(cursor.row))
        scrollUp(cursor.row, in: 0 ..< rows)
        cursor.row = 0
        eraseInDisplay(3)
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
        if sequence.privateMarker != nil, sequence.final == "u" {
            setKeyboardFlags(sequence)
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
            cursor.row = min(topLimit + count - 1, bottomLimit)
            isAfterPrint = false
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
            scrollDown(count, in: scrollRegion)
        case "c" where sequence.parameter(at: 0, default: 0) == 0:
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
        default:
            break
        }
    }

    private mutating func print(_ scalar: Unicode.Scalar) {
        guard scalar.isASCII || scalar.width > 0 else {
            if !combine(scalar), scalar.properties.generalCategory == .spacingMark {
                place(scalar)
            }
            return
        }
        if !scalar.isASCII, scalar.properties.isEmoji, isAfterPrint, combine(scalar) {
            return
        }
        place(scalar)
    }

    private mutating func place(_ scalar: Unicode.Scalar) {
        guard scalar != " " else {
            place(.writtenSpace(style: style))
            return
        }
        let width = columns > 1 && !scalar.isASCII ? max(scalar.width, 1) : 1
        place(Cell(scalar: scalar, style: style, width: UInt8(width)))
    }

    private mutating func place(_ cell: Cell) {
        let width = Int(cell.width)
        if !usesAutowrap {
            guard !isTextRunClipped, cursor.column + width <= columns else {
                isTextRunClipped = true
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
        isAfterPrint = true
    }

    private mutating func clearWideCharacter(at column: Int) {
        breakTab(at: column, row: cursor.row)
        switch screen[cursor.row][column].width {
        case 0 where column > 0:
            screen[cursor.row][column - 1] = writtenBlank
        case 2 where column + 1 < columns:
            screen[cursor.row][column + 1] = writtenBlank
        default:
            break
        }
    }

    private mutating func combine(_ scalar: Unicode.Scalar) -> Bool {
        var column = isWrapPending || isTextRunClipped ? cursor.column : cursor.column - 1
        if isTextRunClipped, screen[cursor.row][cursor.column].isBlank {
            return true
        }
        if column > 0, screen[cursor.row][column].width == 0 {
            column -= 1
        }
        guard column >= 0 else {
            return false
        }
        let target = screen[cursor.row][column]
        if target.isTab || target.isTabGap {
            guard column + 1 < columns, screen[cursor.row][column + 1].isTabGap else {
                if target.isTabGap {
                    screen[cursor.row][column] = Cell(scalar: scalar, style: target.style)
                }
                return true
            }
            breakTab(at: column, row: cursor.row)
        }
        var text = String(graphemes.character(of: screen[cursor.row][column]))
        guard text.unicodeScalars.count < Self.maximumScalarsPerCell,
            scalar.properties.generalCategory != .spacingMark || text.unicodeScalars.first?.width != 0
        else {
            return false
        }
        text.unicodeScalars.append(scalar)
        guard let character = text.first, text.count == 1 else {
            return false
        }
        if graphemes.needsCompaction(for: character) {
            compactGraphemes()
        }
        let cell = graphemes.cell(screen[cursor.row][column], with: character)
        guard graphemes.character(of: cell).unicodeScalars.elementsEqual(character.unicodeScalars) else {
            return false
        }
        screen[cursor.row][column] = cell
        if scalar.width > 0, let base = text.unicodeScalars.first,
            !scalar.properties.isEmojiModifier || base.properties.isEmojiModifierBase
        {
            widen(column)
        }
        return true
    }

    private mutating func widen(_ column: Int) {
        guard screen[cursor.row][column].width == 1, columns > 1 else {
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
        } else {
            cursor.column += 1
        }
    }

    package func character(of cell: Cell) -> Character {
        graphemes.character(of: cell)
    }

    private mutating func compactGraphemes() {
        var used = Array(repeating: false, count: graphemes.count)
        Graphemes.markIndices(in: scrollback, into: &used)
        Graphemes.markIndices(in: screen, into: &used)
        if let normalScreen {
            Graphemes.markIndices(in: normalScreen.lines, into: &used)
        }
        if let alternateScreen {
            Graphemes.markIndices(in: alternateScreen.lines, into: &used)
        }
        let newIndices = graphemes.compact(keeping: used)
        Graphemes.remapIndices(in: &scrollback, with: newIndices)
        Graphemes.remapIndices(in: &screen, with: newIndices)
        if var normalScreen {
            Graphemes.remapIndices(in: &normalScreen.lines, with: newIndices)
            self.normalScreen = normalScreen
        }
        if var alternateScreen {
            Graphemes.remapIndices(in: &alternateScreen.lines, with: newIndices)
            self.alternateScreen = alternateScreen
        }
    }

    private mutating func lineFeed() {
        isWrapPending = false
        isAfterPrint = false
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
        screen[cursor.row].removeLast(count)
        for column in [cursor.column, cursor.column + count, columns] {
            blankBrokenWideCharacter(at: column, row: cursor.row)
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        let count = min(count, columns - cursor.column)
        breakTab(at: cursor.column, row: cursor.row)
        breakTab(at: cursor.column + count - 1, row: cursor.row)
        screen[cursor.row].removeSubrange(cursor.column ..< cursor.column + count)
        screen[cursor.row].append(contentsOf: repeatElement(blank, count: count))
        blankBrokenWideCharacter(at: cursor.column, row: cursor.row)
    }

    private mutating func blankBrokenWideCharacter(at column: Int, row: Int) {
        if column > 0, screen[row][column - 1].width == 2, column == columns || screen[row][column].width != 0 {
            screen[row][column - 1] = writtenBlank
        }
        if column < columns, screen[row][column].width == 0, column == 0 || screen[row][column - 1].width != 2 {
            screen[row][column] = writtenBlank
        }
    }

    private mutating func insertLines(_ count: Int) {
        guard scrollRegion.contains(cursor.row) else {
            return
        }
        scrollDown(count, in: cursor.row ..< scrollRegion.upperBound)
    }

    private mutating func deleteLines(_ count: Int) {
        guard scrollRegion.contains(cursor.row) else {
            return
        }
        if cursor.row == 0 {
            scrollRegionUp(count)
            return
        }
        scrollUp(count, in: cursor.row ..< scrollRegion.upperBound)
        unwrapLine(before: cursor.row)
    }

    private mutating func setScrollRegion(top: Int, bottom: Int) {
        guard top < bottom - 1 else {
            return
        }
        scrollRegion = top ..< bottom
        moveCursor(row: topLimit, column: 0)
    }

    private mutating func keepInScrollback(_ lines: ArraySlice<Line>) {
        var previousLine: Line?
        var keptLine = Line()
        for line in lines {
            if line != previousLine {
                let end = line.isWrapped ? line.count : (line.lastIndex { !$0.isBlank } ?? -1) + 1
                keptLine = end == line.count ? line : Line(line[..<end])
                previousLine = line
            }
            scrollback.append(keptLine)
        }
        trimScrollback()
    }

    private mutating func trimScrollback() {
        if scrollback.count > Self.maximumScrollback + Self.scrollbackTrimCount {
            removedScrollbackCount += scrollback.count - Self.maximumScrollback
            scrollback.removeFirst(scrollback.count - Self.maximumScrollback)
            graphemes.resetCompactionInterval()
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
        if region.lowerBound > 0 {
            unwrapLine(before: region.lowerBound)
        }
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
        } else if normalScreen == nil, !scrollback.isEmpty {
            scrollback[scrollback.count - 1].isWrapped = false
        }
    }

    private mutating func reverseLineFeed() {
        isWrapPending = false
        isAfterPrint = false
        if cursor.row == scrollRegion.lowerBound {
            scrollDown(1, in: scrollRegion)
        } else {
            cursor.row = cursor.row == 0 ? rows - 1 : cursor.row - 1
        }
    }

    private var topLimit: Int {
        usesOriginMode ? scrollRegion.lowerBound : 0
    }

    private var bottomLimit: Int {
        usesOriginMode ? scrollRegion.upperBound - 1 : rows - 1
    }

    private mutating func carriageReturn() {
        isWrapPending = false
        isAfterPrint = false
        cursor.column = 0
    }

    private mutating func moveCursor(row: Int, column: Int) {
        isWrapPending = false
        isAfterPrint = false
        cursor = Position(row: min(max(row, 0), rows - 1), column: min(max(column, 0), columns - 1))
    }

    private mutating func perform(_ command: String) {
        guard let separator = command.unicodeScalars.firstIndex(of: ";") else {
            return
        }
        let text = command[command.unicodeScalars.index(after: separator)...]
        let number = Int(command[..<separator]).flatMap { $0 <= Int32.max ? $0 : nil } ?? 0
        switch number {
        case 0, 2:
            title = String(text)
        case 7:
            setCurrentDirectory(text)
        case 10:
            reportColors(text, from: 0)
        case 11:
            reportColors(text, from: 1)
        default:
            break
        }
    }

    private mutating func reset() {
        var terminal = Terminal(columns: columns, rows: rows)
        terminal.title = title
        terminal.bellCount = bellCount
        terminal.reportedColors = reportedColors
        terminal.graphemes = graphemes
        terminal.scrollback = scrollback
        scrollback = []
        terminal.unwrapLine(before: 0)
        terminal.removedScrollbackCount = removedScrollbackCount
        terminal.decoder = decoder
        terminal.replies = replies
        terminal.isWrapPending = isWrapPending
        terminal.usesAutowrap = usesAutowrap
        self = terminal
    }

    private mutating func fillScreen() {
        screen = Array(repeating: Line(repeatElement(Cell(scalar: "E"), count: columns)), count: rows)
        unwrapLine(before: 0)
    }

    private mutating func softReset() {
        usesInsertMode = false
        usesNewLineMode = false
        usesApplicationCursorKeys = false
        usesOriginMode = false
        usesReverseVideo = false
        tabStops = Self.defaultTabStops(0 ..< columns)
        isCursorVisible = true
        cursorShape = .block
        scrollRegion = 0 ..< rows
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
        while end < columns, screen[row][end].isTabGap {
            end += 1
        }
        for index in start ..< end {
            screen[row][index] = .writtenSpace(style: screen[row][index].style)
        }
    }

    private mutating func moveForward(tabStops count: Int) {
        isWrapPending = false
        isAfterPrint = false
        for _ in 0 ..< min(count, columns) {
            cursor.column = tabStops[(cursor.column + 1)...].firstIndex(of: true) ?? columns - 1
        }
    }

    private mutating func moveBackward(_ count: Int) {
        var row = cursor.row
        var column = cursor.column - count
        while column < 0, row > 0, screen[row - 1].isWrapped {
            row -= 1
            column += columns
        }
        if column < 0, row == 0, normalScreen == nil, scrollback.last?.isWrapped == true {
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
        case (1006, _):
            usesSGRMouseEncoding = isEnabled
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
        cursor = Position(row: topLimit, column: 0)
        isAfterPrint = false
    }

    private mutating func enterAlternateScreen() {
        guard normalScreen == nil else {
            return
        }
        normalScreen = (screen, cursor, savedCursor)
        screen = Array(repeating: Self.blankLine(columns: columns), count: rows)
        if let alternateScreen, alternateScreen.lines.count == rows, alternateScreen.lines.first?.count == columns {
            screen = alternateScreen.lines
        }
        savedCursor = alternateScreen?.savedCursor ?? SavedCursor()
    }

    private mutating func exitAlternateScreen() {
        guard let normalScreen else {
            return
        }
        alternateScreen = (screen, savedCursor)
        screen = normalScreen.lines
        savedCursor = normalScreen.savedCursor
        self.normalScreen = nil
    }

    private mutating func setKeyboardFlags(_ sequence: EscapeSequenceParser.ControlSequence) {
        let index = isAlternateScreenActive ? 1 : 0
        let flags = sequence.parameter(at: 0, default: 0) & 1
        switch sequence.privateMarker {
        case "?":
            replies += "\u{1B}[?\(keyboardFlagStacks[index].last ?? 0)u".utf8
        case ">":
            keyboardFlagStacks[index] = Array(
                (keyboardFlagStacks[index] + [flags]).suffix(Self.maximumKeyboardFlagsDepth))
        case "<":
            keyboardFlagStacks[index] = Array(keyboardFlagStacks[index].dropLast(sequence.parameters.first ?? 1))
        case "=":
            let current = keyboardFlagStacks[index].popLast() ?? 0
            let newFlags =
                switch sequence.parameters.dropFirst().first ?? 1 {
                case 1: flags
                case 2: current | flags
                case 3: current & ~flags
                default: current
                }
            keyboardFlagStacks[index].append(newFlags)
        default:
            break
        }
    }

    private mutating func reportStatus(_ request: Int) {
        switch request {
        case 5:
            replies += "\u{1B}[0n".utf8
        case 6:
            replies += "\u{1B}[\(cursor.row - topLimit + 1);\(cursor.column + 1)R".utf8
        default:
            break
        }
    }

    private mutating func reportColors(_ queries: Substring, from first: Int) {
        let queries = queries.split(separator: ";", omittingEmptySubsequences: false)
        for (index, query) in zip(reportedColors.indices.dropFirst(first), queries) where query == "?" {
            let color = reportedColors[usesReverseVideo ? 1 - index : index]
            let rgb = String(format: "rgb:%04x/%04x/%04x", color.red, color.green, color.blue)
            replies += "\u{1B}]\(10 + index);\(rgb)\u{1B}\\".utf8
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
            if normalScreen == nil, screen.contains(where: { $0.contains(where: \.isWritten) }) {
                keepInScrollback(screen[...])
            }
            unwrapLine(before: 0)
            screen = blankLines(rows)
        case 3:
            normalScreen?.lines = Array(repeating: Self.blankLine(columns: columns), count: rows)
            removedScrollbackCount += scrollback.count
            scrollback.removeAll()
            graphemes.resetCompactionInterval()
        default:
            break
        }
    }

    private mutating func eraseInLine(_ mode: Int) {
        switch mode {
        case 0:
            erase(cursor.column ..< columns, row: cursor.row, with: blank)
        case 1:
            erase(0 ..< cursor.column + 1, row: cursor.row, with: writtenBlank)
        case 2:
            erase(0 ..< columns, row: cursor.row, with: blank)
        default:
            break
        }
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

    private static func resized(_ screen: [Line], columns: Int, rows: Int, removingFirst removedRows: Int)
        -> [Line]
    {
        let lines = screen.dropFirst(removedRows).prefix(rows)
            .map { fitted($0, columns: columns) }
        return lines + Array(repeating: blankLine(columns: columns), count: rows - lines.count)
    }

    private static func fitted(_ line: Line, columns: Int) -> Line {
        var line = Line(line.prefix(columns), isWrapped: line.isWrapped)
        line.append(contentsOf: repeatElement(Cell(), count: max(columns - line.count, 0)))
        if line[columns - 1].width == 2 {
            line[columns - 1] = Cell()
        }
        return line
    }

    private static func blankLine(columns: Int) -> Line {
        Line(repeatElement(Cell(), count: columns))
    }
}
