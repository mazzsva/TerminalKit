extension Terminal {
    package struct Scrollback: RandomAccessCollection, Sendable {
        private struct Paragraph: Sendable {
            private struct Detail: Sendable {
                var widths: Widths?
                var rowOffsets: [Int]?
            }

            var start: Int
            var textCount: Int
            var lastRowTextCount: Int
            var rowTextCount = 0
            var isSimple: Bool
            private var details: [Detail]?

            init(start: Int, textCount: Int, isSimple: Bool) {
                self.start = start
                self.textCount = textCount
                lastRowTextCount = textCount
                self.isSimple = isSimple
            }

            var widths: Widths? {
                details?[0].widths
            }

            var rowOffsets: [Int]? {
                details?[0].rowOffsets
            }

            var needsMarks: Bool {
                details?[0].widths?.needsMarks ?? true
            }

            func rowCount(of lines: ArraySlice<Line>, columns: Int) -> (rows: Int, used: Int) {
                details?[0].widths?.rowCount(columns: columns) ?? Widths(lines).rowCount(columns: columns)
            }

            mutating func updateWidths(of lines: ArraySlice<Line>, _ body: (inout Widths) -> Void) {
                var details = self.details ?? [Detail()]
                self.details = nil
                var widths = details[0].widths ?? Widths(lines)
                details[0].widths = nil
                body(&widths)
                details[0].widths = widths
                self.details = details
            }

            mutating func setRowOffsets(_ rowOffsets: [Int]?) {
                var details = self.details ?? [Detail()]
                self.details = nil
                details[0].rowOffsets = rowOffsets
                self.details = details
            }
        }

        private(set) var lines: [Line] = []
        private var paragraphs: [Paragraph] = []
        private var rowEnds: [Int] = []
        private(set) var relaidCount = 0
        private var columns: Int

        init(columns: Int) {
            self.columns = columns
        }

        package var startIndex: Int {
            0
        }

        package var endIndex: Int {
            rowEnds.last ?? 0
        }

        var isLastRowWrapped: Bool {
            lines.last?.isWrapped ?? false
        }

        package subscript(row: Int) -> Line {
            precondition(indices.contains(row))
            var lower = 0
            var upper = rowEnds.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if rowEnds[middle] > row {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            return self.row(row - rowStart(of: lower), of: lower)
        }

        package func makeIterator() -> Iterator {
            Iterator(scrollback: self)
        }

        package func map<T>(_ transform: (Line) throws -> T) rethrows -> [T] {
            var result: [T] = []
            result.reserveCapacity(count)
            for line in self {
                result.append(try transform(line))
            }
            return result
        }

        mutating func append(_ line: Line) {
            let textCount = line.textCount
            let isSimple = line[..<textCount].allSatisfy { $0.width == 1 && !$0.isTab && !$0.isTabGap }
            guard isLastRowWrapped, let last = paragraphs.indices.last else {
                paragraphs.append(Paragraph(start: lines.count, textCount: textCount, isSimple: isSimple))
                lines.append(line)
                rowEnds.append(endIndex + 1)
                return
            }
            let start = paragraphs[last].start
            if lines.count - start == 1 {
                paragraphs[last].rowTextCount = paragraphs[last].lastRowTextCount
            } else if paragraphs[last].rowTextCount != paragraphs[last].lastRowTextCount {
                paragraphs[last].rowTextCount = -1
            }
            paragraphs[last].textCount += textCount
            paragraphs[last].lastRowTextCount = textCount
            if paragraphs[last].rowOffsets != nil {
                paragraphs[last].setRowOffsets(nil)
            }
            paragraphs[last].isSimple = paragraphs[last].isSimple && isSimple
            if !paragraphs[last].isSimple {
                paragraphs[last].updateWidths(of: lines[start...]) { $0.append(line[..<textCount]) }
            }
            lines.append(line)
            rowEnds[last] = rowStart(of: last) + rowCount(of: last, columns: columns, isRelaid: last < relaidCount)
        }

        mutating func unwrapLastRow() {
            if !lines.isEmpty {
                lines[lines.count - 1].isWrapped = false
            }
        }

        mutating func removeAll() {
            lines.removeAll()
            paragraphs.removeAll()
            rowEnds.removeAll()
            relaidCount = 0
        }

        mutating func removeLast(coveringRows rows: Int, columns: Int) -> [Line] {
            var first = paragraphs.count
            var coveredRows = 0
            while first > 0, coveredRows < rows {
                first -= 1
                coveredRows += rowCount(of: first, columns: columns, isRelaid: true)
            }
            guard first < paragraphs.count else {
                return []
            }
            let start = paragraphs[first].start
            let removed = Array(lines[start...])
            lines.removeSubrange(start...)
            paragraphs.removeSubrange(first...)
            rowEnds.removeSubrange(first...)
            relaidCount = Swift.min(relaidCount, first)
            return removed
        }

        mutating func relayOut(columns: Int) {
            self.columns = columns
            relaidCount = paragraphs.count
            var end = 0
            for index in paragraphs.indices {
                if !paragraphs[index].isSimple, paragraphs[index].textCount > columns,
                    paragraphs[index].needsMarks
                {
                    paragraphs[index].updateWidths(of: lines[storedRange(of: index)]) { $0.markRows(columns: columns) }
                }
                if paragraphs[index].rowTextCount < 0, paragraphs[index].rowOffsets == nil {
                    var offset = 0
                    paragraphs[index]
                        .setRowOffsets(
                            lines[storedRange(of: index)]
                                .map { line in
                                    defer { offset += line.textCount }
                                    return offset
                                })
                }
                end += rowCount(of: index, columns: columns, isRelaid: true)
                rowEnds[index] = end
            }
        }

        private func rowStart(of paragraph: Int) -> Int {
            paragraph > 0 ? rowEnds[paragraph - 1] : 0
        }

        private func storedRange(of paragraph: Int) -> Range<Int> {
            paragraphs[paragraph].start
                ..< (paragraph + 1 < paragraphs.count ? paragraphs[paragraph + 1].start : lines.count)
        }

        private func rowCount(of index: Int, columns: Int, isRelaid: Bool) -> Int {
            let range = storedRange(of: index)
            guard isRelaid else {
                return range.count
            }
            let textCount = paragraphs[index].textCount
            if range.count == 1, textCount <= columns {
                return 1
            }
            let isSimple = paragraphs[index].isSimple
            if !isSimple, columns == 1 {
                return Terminal.laidOut(lines[range], columns: columns).count
            }
            let (rows, used) =
                isSimple
                ? Widths.simpleRowCount(textCount: textCount, columns: columns)
                : paragraphs[index].rowCount(of: lines[range], columns: columns)
            return rows + (keepsEmptyRow(index, storedRows: range.count, used: used, columns: columns) ? 1 : 0)
        }

        private func keepsEmptyRow(_ index: Int, storedRows: Int, used: Int, columns: Int) -> Bool {
            storedRows > 1 && paragraphs[index].lastRowTextCount == 0 && used == columns
        }

        fileprivate func isCheap(_ index: Int) -> Bool {
            index >= relaidCount || columns > 1 || paragraphs[index].isSimple
                || (storedRange(of: index).count == 1 && paragraphs[index].textCount <= columns)
        }

        fileprivate func row(_ row: Int, of index: Int) -> Line {
            let range = storedRange(of: index)
            guard index < relaidCount else {
                return lines[range.lowerBound + row]
            }
            let paragraph = paragraphs[index]
            if range.count == 1, paragraph.textCount <= columns {
                return Terminal.relaidRow(lines[range.lowerBound], columns: columns)
            }
            guard paragraph.isSimple || columns > 1 else {
                return Terminal.laidOut(lines[range], columns: columns)[row]
            }
            let widths = paragraph.isSimple ? nil : paragraph.widths ?? Widths(lines[range])
            let last = lines[range.upperBound - 1]
            var rows = rowCount(of: index)
            var keepsEmptyRow = false
            if row == rows - 1 {
                let used: Int
                (rows, used) =
                    widths?.rowCount(columns: columns)
                    ?? Widths.simpleRowCount(textCount: paragraph.textCount, columns: columns)
                keepsEmptyRow = self.keepsEmptyRow(index, storedRows: range.count, used: used, columns: columns)
            }
            guard row < rows else {
                return Terminal.trimmed(Line([], isWrapped: last.isWrapped))
            }
            let bounds =
                widths?.bounds(ofRow: row, columns: columns)
                ?? Widths.simpleBounds(ofRow: row, textCount: paragraph.textCount, columns: columns)
            var line = cells(bounds.cells, of: paragraph, storedRange: range)
            if row < rows - 1 {
                line.isWrapped = true
                line.append(contentsOf: repeatElement(.padding, count: Swift.max(columns - bounds.used, 0)))
                return line
            }
            line.isWrapped = keepsEmptyRow || last.isWrapped
            if let fill = last.fill, bounds.used < columns {
                line.append(fill)
            }
            return Terminal.trimmed(line)
        }

        private func cells(_ offsets: Range<Int>, of paragraph: Paragraph, storedRange range: Range<Int>) -> Line {
            var line = Line()
            line.reserveCapacity(offsets.count + 1)
            var storedRow = range.lowerBound
            var rowStart = 0
            if let rowOffsets = paragraph.rowOffsets {
                var lower = 0
                var upper = rowOffsets.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if rowOffsets[middle] <= offsets.lowerBound {
                        lower = middle + 1
                    } else {
                        upper = middle
                    }
                }
                storedRow += Swift.max(lower - 1, 0)
                rowStart = rowOffsets[Swift.max(lower - 1, 0)]
            } else if paragraph.rowTextCount > 0 {
                storedRow += Swift.min(offsets.lowerBound / paragraph.rowTextCount, range.count - 1)
                rowStart = (storedRow - range.lowerBound) * paragraph.rowTextCount
            }
            var offset = offsets.lowerBound
            while offset < offsets.upperBound {
                let textCount = lines[storedRow].textCount
                if offset < rowStart + textCount {
                    let upper = Swift.min(offsets.upperBound, rowStart + textCount)
                    line.append(contentsOf: lines[storedRow][(offset - rowStart) ..< (upper - rowStart)])
                    offset = upper
                }
                rowStart += textCount
                storedRow += 1
            }
            return line
        }

        fileprivate func rows(of index: Int) -> [Line] {
            Terminal.laidOut(lines[storedRange(of: index)], columns: columns)
        }

        fileprivate func rowCount(of index: Int) -> Int {
            rowEnds[index] - rowStart(of: index)
        }

        fileprivate var paragraphCount: Int {
            paragraphs.count
        }

        private struct Widths: Sendable {
            private enum Kind {
                case cell
                case tab
                case gaps
            }

            private struct Run {
                var kind: Kind
                var width: Int32
                var cells: Int32 = 1
                var count: Int32 = 1

                func breaks(columns: Int, used: Int) -> (count: Int, used: Int) {
                    let width = Int(width)
                    let count = Int(count)
                    if count == 1 || width == 0 {
                        let breaksRow = used > 0 && used + (kind == .gaps ? 1 : width) > columns
                        return (breaksRow ? 1 : 0, (breaksRow ? 0 : used) + width)
                    }
                    if width >= columns {
                        return (count - (used > 0 ? 0 : 1), width)
                    }
                    let fitting = Swift.max(columns - used, 0) / width
                    if count <= fitting {
                        return (0, used + count * width)
                    }
                    let perRow = columns / width
                    let moreBreaks = (count - fitting - 1) / perRow
                    return (1 + moreBreaks, (count - fitting - moreBreaks * perRow) * width)
                }

                func breakPoint(_ number: Int, columns: Int, used: Int) -> (unit: Int, used: Int) {
                    let width = Int(width)
                    if count == 1 || width == 0 {
                        return (0, used)
                    }
                    if width >= columns {
                        let unit = number + (used > 0 ? 0 : 1)
                        return (unit, unit == 0 ? used : width)
                    }
                    let fitting = Swift.max(columns - used, 0) / width
                    let perRow = columns / width
                    return number == 0 ? (fitting, used + fitting * width) : (fitting + number * perRow, perRow * width)
                }
            }

            private struct Mark {
                var run: Int
                var breaks: Int
                var used: Int
                var offset: Int
            }

            private static let runsPerMark = 128

            private var runs: [Run] = []
            private var continuesTab = false
            private var marks: [Mark] = []
            private var markedColumns = 0

            init(_ lines: ArraySlice<Line>) {
                for line in lines {
                    append(line[..<line.textCount])
                }
            }

            static func simpleRowCount(textCount: Int, columns: Int) -> (rows: Int, used: Int) {
                let rows = Swift.max((textCount + columns - 1) / columns, 1)
                return (rows, textCount - (rows - 1) * columns)
            }

            static func simpleBounds(ofRow row: Int, textCount: Int, columns: Int) -> (cells: Range<Int>, used: Int) {
                let cells = row * columns ..< Swift.min((row + 1) * columns, textCount)
                return (cells, cells.count)
            }

            mutating func append(_ cells: Slice<Line>) {
                marks = []
                for cell in cells {
                    if cell.isTabGap, continuesTab {
                        extendLastUnit(width: 1)
                    } else if cell.width == 0 {
                        if runs.isEmpty {
                            runs.append(Run(kind: .cell, width: 0))
                        } else {
                            extendLastUnit(width: 0)
                        }
                    } else {
                        if runs.count > 1, runs[runs.count - 1].kind != .gaps,
                            runs[runs.count - 1].kind == runs[runs.count - 2].kind,
                            runs[runs.count - 1].width == runs[runs.count - 2].width,
                            runs[runs.count - 1].cells == runs[runs.count - 2].cells
                        {
                            runs[runs.count - 2].count += runs.removeLast().count
                        }
                        let kind = cell.isTab ? Kind.tab : cell.isTabGap ? .gaps : .cell
                        runs.append(Run(kind: kind, width: Int32(cell.width)))
                    }
                    continuesTab = cell.isTab || cell.isTabGap
                }
            }

            private mutating func extendLastUnit(width: Int32) {
                let last = runs.count - 1
                if runs[last].count > 1 {
                    runs[last].count -= 1
                    runs.append(
                        Run(kind: runs[last].kind, width: runs[last].width + width, cells: runs[last].cells + 1))
                } else {
                    runs[last].width += width
                    runs[last].cells += 1
                }
            }

            func rowCount(columns: Int) -> (rows: Int, used: Int) {
                var breaks = 0
                var used = 0
                for run in runs {
                    let (count, newUsed) = run.breaks(columns: columns, used: used)
                    breaks += count
                    used = newUsed
                }
                return (breaks + 1, used)
            }

            var needsMarks: Bool {
                runs.count > Self.runsPerMark
            }

            mutating func markRows(columns: Int) {
                guard needsMarks else {
                    return
                }
                marks = []
                markedColumns = columns
                var mark = Mark(run: 0, breaks: 0, used: 0, offset: 0)
                for (index, run) in runs.enumerated() {
                    if index % Self.runsPerMark == 0 {
                        mark.run = index
                        marks.append(mark)
                    }
                    let (count, used) = run.breaks(columns: columns, used: mark.used)
                    mark.breaks += count
                    mark.used = used
                    mark.offset += Int(run.count) * Int(run.cells)
                }
            }

            func bounds(ofRow row: Int, columns: Int) -> (cells: Range<Int>, used: Int) {
                var lower = 0
                var upper = columns == markedColumns ? marks.count : 0
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if marks[middle].breaks < row {
                        lower = middle + 1
                    } else {
                        upper = middle
                    }
                }
                let mark = lower > 0 ? marks[lower - 1] : nil
                var breaks = mark?.breaks ?? 0
                var used = mark?.used ?? 0
                var offset = mark?.offset ?? 0
                var start = 0
                for run in runs[(mark?.run ?? 0)...] {
                    let (count, newUsed) = run.breaks(columns: columns, used: used)
                    if row > 0, breaks < row, breaks + count >= row {
                        start =
                            offset + run.breakPoint(row - breaks - 1, columns: columns, used: used).unit
                            * Int(run.cells)
                    }
                    if breaks + count > row {
                        let point = run.breakPoint(row - breaks, columns: columns, used: used)
                        return (start ..< offset + point.unit * Int(run.cells), point.used)
                    }
                    breaks += count
                    used = newUsed
                    offset += Int(run.count) * Int(run.cells)
                }
                return (start ..< offset, used)
            }
        }

        package struct Iterator: IteratorProtocol {
            private let scrollback: Scrollback
            private var paragraph = 0
            private var row = 0
            private var rows: [Line]?

            fileprivate init(scrollback: Scrollback) {
                self.scrollback = scrollback
            }

            package mutating func next() -> Line? {
                guard paragraph < scrollback.paragraphCount else {
                    return nil
                }
                let line: Line
                if scrollback.isCheap(paragraph) {
                    line = scrollback.row(row, of: paragraph)
                } else {
                    let rows = rows ?? scrollback.rows(of: paragraph)
                    self.rows = rows
                    line = rows[row]
                }
                row += 1
                if row == scrollback.rowCount(of: paragraph) {
                    paragraph += 1
                    row = 0
                    rows = nil
                }
                return line
            }
        }
    }

    static func trimmed(_ line: Line) -> Line {
        guard !line.isWrapped else {
            return line
        }
        let end = (line.lastIndex { !$0.isBlank } ?? -1) + 1
        return end == line.count ? line : Line(line[..<end])
    }

    static func relaidRow(_ line: Line, columns: Int) -> Line {
        let kept = Swift.max(min((line.lastIndex { !$0.isBlank } ?? -1) + 1, columns), line.textCount)
        return trimmed(kept == line.count ? line : Line(line.prefix(kept), isWrapped: line.isWrapped))
    }

    static func laidOut(_ lines: ArraySlice<Line>, columns: Int) -> [Line] {
        reflow(Array(lines), columns: columns, cursor: nil).lines.map(trimmed)
    }
}
