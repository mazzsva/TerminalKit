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
        var isWrapPending = false
        var usesLineDrawing = false
    }

    private static let tabWidth = 8
    private static let maximumScalarsPerCell = 16
    private static let maximumScrollback = 10_000
    private static let scrollbackTrimCount = 1_000
    private static let maximumKeyboardFlagsDepth = 8

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
    package internal(set) var links = Links()
    package private(set) var bellCount = 0
    package internal(set) var currentDirectory: URL?
    package private(set) var mouseTracking = MouseTracking.off
    package private(set) var synchronizedOutputCount = 0
    package var reportedColors: [RGB] = []
    private(set) var usesSGRMouseEncoding = false

    package var isAlternateScreenActive: Bool {
        normalScreen != nil
    }

    package var usesDisambiguatedKeys: Bool {
        keyboardFlagStacks[isAlternateScreenActive ? 1 : 0].last == 1
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
        snapshot.graphemes = graphemes
        snapshot.links = links
        return snapshot
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
    private var normalScreen: (lines: [Line], cursor: Position, savedCursor: SavedCursor)?
    private var synchronizedSnapshot: [Terminal] = []
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
        endSynchronizedOutput()
        if columns != self.columns {
            guard var normalScreen else {
                let (lines, anchors) = reflow(
                    screen,
                    keeping: [(cursor, isWrapPending), (savedCursor.position, savedCursor.isWrapPending)],
                    columns: columns,
                    rows: rows
                )
                screen = lines
                (cursor, isWrapPending) = anchors[0]
                (savedCursor.position, savedCursor.isWrapPending) = anchors[1]
                setSize(columns: columns, rows: rows)
                return
            }
            let saved = normalScreen.savedCursor
            let (lines, anchors) = reflow(
                normalScreen.lines,
                keeping: [(normalScreen.cursor, false), (saved.position, saved.isWrapPending)],
                columns: columns,
                rows: rows
            )
            normalScreen.lines = lines
            normalScreen.cursor = anchors[0].position
            (normalScreen.savedCursor.position, normalScreen.savedCursor.isWrapPending) = anchors[1]
            self.normalScreen = normalScreen
            savedCursor.isWrapPending = false
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
            switch action {
            case .print(let scalar):
                print(usesLineDrawing ? scalar.lineDrawingCharacter : scalar)
            case .execute("\n"), .execute("\u{B}"), .execute("\u{C}"):
                lineFeed()
            case .execute("\r"):
                carriageReturn()
            case .execute("\u{7}"):
                bellCount += 1
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

    package mutating func endSynchronizedOutput() {
        synchronizedSnapshot = []
    }

    private mutating func perform(_ sequence: EscapeSequenceParser.ControlSequence) {
        if sequence.privateMarker == nil, sequence.intermediates == " ", sequence.final == "q" {
            setCursorShape(sequence.parameter(at: 0, default: 0))
            return
        }
        if sequence.intermediates == "$", sequence.final == "p",
            sequence.privateMarker == nil || sequence.privateMarker == "?"
        {
            reportMode(sequence.parameter(at: 0, default: 0), isPrivate: sequence.privateMarker == "?")
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
        guard
            sequence.privateMarker == nil
                || sequence.privateMarker == "?" && (sequence.final == "J" || sequence.final == "K")
        else {
            return
        }
        let count = sequence.parameter(at: 0, default: 1)
        switch sequence.final {
        case "A":
            moveCursor(row: max(cursor.row - count, topLimit), column: cursor.column)
        case "B", "e":
            moveCursor(row: min(cursor.row + count, bottomLimit), column: cursor.column)
        case "C", "a":
            moveCursor(row: cursor.row, column: cursor.column + count)
        case "D":
            moveCursor(row: cursor.row, column: cursor.column - count)
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
            if let lastCharacter, !lastCharacter.properties.isEmojiModifier,
                !("\u{1F1E6}" ... "\u{1F1FF}").contains(lastCharacter)
            {
                repeatCharacter(lastCharacter, count: count)
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
        if !scalar.isASCII, scalar.properties.isEmoji, combine(scalar) {
            return
        }
        place(scalar)
    }

    private mutating func place(_ scalar: Unicode.Scalar) {
        lastCharacter = scalar
        let width = columns > 1 ? scalar.width : 1
        if isWrapPending || cursor.column + width > columns {
            if usesAutowrap {
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

    private mutating func repeatCharacter(_ scalar: Unicode.Scalar, count: Int) {
        print(scalar)
        let width = columns > 1 ? scalar.width : 1
        let rowCount = columns / width
        guard usesAutowrap else {
            for _ in 0 ..< min(count - 1, rowCount + 2) {
                print(scalar)
            }
            return
        }
        let screenCount = (2 * rows - cursor.row) * rowCount
        var remaining = count - 1 <= screenCount ? count - 1 : screenCount + (count - 1 - screenCount) % rowCount
        while remaining > 0, !isWrapPending, cursor.column + width <= columns {
            place(scalar)
            remaining -= 1
        }
        let cells = [Cell(scalar: scalar, style: style, width: UInt8(width)), Cell(style: style, width: 0)]
        var line = Line((0 ..< columns).map { cells[$0 % width] })
        while remaining >= rowCount {
            place(scalar)
            if columns % width != 0 {
                let end = screen[cursor.row][usesInsertMode ? 2 : columns - 1]
                let isBroken = usesInsertMode ? end.width == 2 : screen[cursor.row][columns - 2].width == 2
                line[columns - 1] = isBroken ? blank : end
            }
            line.isWrapped = screen[cursor.row].isWrapped
            screen[cursor.row] = line
            cursor.column = columns - 1
            isWrapPending = columns % width == 0
            remaining -= rowCount
        }
        for _ in 0 ..< remaining {
            place(scalar)
        }
    }

    @discardableResult
    private mutating func combine(_ scalar: Unicode.Scalar) -> Bool {
        var column = isWrapPending ? cursor.column : cursor.column - 1
        if column > 0, screen[cursor.row][column].width == 0 {
            column -= 1
        }
        guard column >= 0 else {
            return false
        }
        var text = String(graphemes.character(of: screen[cursor.row][column]))
        guard text.unicodeScalars.count < Self.maximumScalarsPerCell else {
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
        guard graphemes.character(of: cell) == character else {
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
        guard screen[cursor.row][column].width == 1, cursor.column == column + 1 else {
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

    private mutating func setLink(_ value: Substring) {
        guard let (key, uri) = Links.key(from: value) else {
            return
        }
        guard !uri.isEmpty else {
            style.link = 0
            return
        }
        if links.needsCompaction(forKey: key, uri: uri) {
            compactLinks()
        }
        style.link = links.link(forKey: key, uri: uri)
    }

    private mutating func compactLinks() {
        endSynchronizedOutput()
        var used = Array(repeating: false, count: links.count)
        Links.markLinks(in: scrollback, into: &used)
        Links.markLinks(in: screen, into: &used)
        for link in [savedCursor.style.link, normalScreen?.savedCursor.style.link ?? 0] {
            used[Int(link)] = true
        }
        if let normalScreen {
            Links.markLinks(in: normalScreen.lines, into: &used)
        }
        let newIndices = links.compact(keeping: used)
        Links.remapLinks(in: &scrollback, with: newIndices)
        Links.remapLinks(in: &screen, with: newIndices)
        savedCursor.style.link = newIndices[Int(savedCursor.style.link)]
        if var normalScreen {
            Links.remapLinks(in: &normalScreen.lines, with: newIndices)
            normalScreen.savedCursor.style.link = newIndices[Int(normalScreen.savedCursor.style.link)]
            self.normalScreen = normalScreen
        }
    }

    private mutating func compactGraphemes() {
        endSynchronizedOutput()
        var used = Array(repeating: false, count: graphemes.count)
        Graphemes.markIndices(in: scrollback, into: &used)
        Graphemes.markIndices(in: screen, into: &used)
        if let normalScreen {
            Graphemes.markIndices(in: normalScreen.lines, into: &used)
        }
        let newIndices = graphemes.compact(keeping: used)
        Graphemes.remapIndices(in: &scrollback, with: newIndices)
        Graphemes.remapIndices(in: &screen, with: newIndices)
        if var normalScreen {
            Graphemes.remapIndices(in: &normalScreen.lines, with: newIndices)
            self.normalScreen = normalScreen
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
        unwrapLine(before: cursor.row)
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
            links.resetCompactionInterval()
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
        if cursor.row == scrollRegion.lowerBound {
            scrollDown(1, in: scrollRegion)
        } else if cursor.row > 0 {
            cursor.row -= 1
        }
    }

    private var topLimit: Int {
        cursor.row >= scrollRegion.lowerBound ? scrollRegion.lowerBound : 0
    }

    private var bottomLimit: Int {
        cursor.row < scrollRegion.upperBound ? scrollRegion.upperBound - 1 : rows - 1
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
        guard parts.count == 2 else {
            return
        }
        switch parts[0] {
        case "0", "2":
            title = String(parts[1])
        case "8":
            setLink(parts[1])
        case "7":
            setCurrentDirectory(parts[1])
        case "10":
            reportColors(parts[1], from: 0)
        case "11":
            reportColors(parts[1], from: 1)
        default:
            break
        }
    }

    private mutating func reset() {
        var terminal = Terminal(columns: columns, rows: rows)
        terminal.title = title
        terminal.bellCount = bellCount
        terminal.currentDirectory = currentDirectory
        terminal.synchronizedOutputCount = synchronizedOutputCount
        terminal.reportedColors = reportedColors
        terminal.graphemes = graphemes
        terminal.links = links
        terminal.scrollback = scrollback
        scrollback = []
        terminal.unwrapLine(before: 0)
        terminal.removedScrollbackCount = removedScrollbackCount
        terminal.decoder = decoder
        terminal.replies = replies
        self = terminal
    }

    private mutating func softReset() {
        usesInsertMode = false
        usesApplicationCursorKeys = false
        usesAutowrap = true
        isCursorVisible = true
        cursorShape = .block
        scrollRegion = 0 ..< rows
        style = Style()
        usesLineDrawing = false
        savedCursor = SavedCursor()
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
        case (47, true), (1047, true):
            enterAlternateScreen()
        case (47, false), (1047, false):
            exitAlternateScreen()
        case (1048, true):
            saveCursor()
        case (1048, false):
            restoreCursor()
        case (1049, true):
            saveCursor()
            enterAlternateScreen()
        case (1049, false):
            exitAlternateScreen()
            restoreCursor()
        case (2026, true) where synchronizedSnapshot.isEmpty:
            var snapshot = self
            snapshot.scrollback = []
            synchronizedSnapshot = [snapshot]
            synchronizedOutputCount += 1
        case (2026, false):
            endSynchronizedOutput()
        default:
            break
        }
    }

    private mutating func enterAlternateScreen() {
        guard normalScreen == nil else {
            return
        }
        normalScreen = (screen, cursor, savedCursor)
        screen = blankLines(rows)
        savedCursor = SavedCursor()
    }

    private mutating func exitAlternateScreen() {
        guard let normalScreen else {
            return
        }
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

    private mutating func reportMode(_ mode: Int, isPrivate: Bool) {
        let isEnabled = isPrivate ? isPrivateModeEnabled(mode) : mode == 4 ? usesInsertMode : nil
        let status = isEnabled.map { $0 ? 1 : 2 } ?? 0
        replies += "\u{1B}[\(isPrivate ? "?" : "")\(mode);\(status)$y".utf8
    }

    private func isPrivateModeEnabled(_ mode: Int) -> Bool? {
        switch mode {
        case 1: usesApplicationCursorKeys
        case 5: usesReverseVideo
        case 7: usesAutowrap
        case 25: isCursorVisible
        case 47, 1047, 1049: isAlternateScreenActive
        case 1000: mouseTracking == .clicks
        case 1002: mouseTracking == .drags
        case 1003: mouseTracking == .anyMotion
        case 1004: usesFocusReporting
        case 1006: usesSGRMouseEncoding
        case 2004: usesBracketedPaste
        case 2026: isSynchronizingOutput
        default: nil
        }
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
            if cursor.column == 0 {
                unwrapLine(before: cursor.row)
            }
            eraseInLine(0)
            for row in cursor.row + 1 ..< rows {
                erase(0 ..< columns, row: row)
            }
        case 1:
            unwrapLine(before: 0)
            for row in 0 ..< cursor.row {
                erase(0 ..< columns, row: row)
            }
            eraseInLine(1)
        case 2:
            unwrapLine(before: 0)
            isWrapPending = false
            screen = blankLines(rows)
        case 3:
            removedScrollbackCount += scrollback.count
            scrollback.removeAll()
            graphemes.resetCompactionInterval()
            links.resetCompactionInterval()
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
