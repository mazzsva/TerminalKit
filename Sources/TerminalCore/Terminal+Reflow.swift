extension Terminal {
    static func reflow(_ lines: [Line], columns: Int, cursor: Position?) -> (lines: [Line], cursor: Position?) {
        var result: [Line] = []
        result.reserveCapacity(lines.count)
        var reflowedCursor: Position?
        var start = 0
        while start < lines.count {
            var end = start
            while end < lines.count - 1, lines[end].isWrapped {
                end += 1
            }
            defer { start = end + 1 }
            let hasCursor = cursor.map { (start ... end).contains($0.row) } ?? false
            let textCount = lines[end].textCount
            if start == end, textCount <= columns, !hasCursor {
                let line = lines[start]
                let kept = max(min((line.lastIndex { !$0.isBlank } ?? -1) + 1, columns), textCount)
                result.append(kept == line.count ? line : Line(line.prefix(kept), isWrapped: line.isWrapped))
                continue
            }
            var cells: [Cell] = []
            var cursorOffset: Int?
            var isPastEnd = false
            for row in start ... end {
                let rowCount = lines[row].textCount
                if let cursor, cursor.row == row {
                    cursorOffset = cells.count + min(cursor.column, rowCount)
                    isPastEnd = row == end && cursor.column > rowCount
                }
                cells.append(contentsOf: lines[row][..<rowCount])
            }
            if var offset = cursorOffset, offset < cells.count {
                while offset > 0, cells[offset].isTabGap || cells[offset].width == 0 {
                    offset -= 1
                }
                cursorOffset = offset
            }
            if columns == 1 {
                let kept = cursorOffset.map { cells[..<min($0, cells.count)].count { $0.width > 0 } }
                cursorOffset = kept
                cells = cells.filter { $0.width > 0 }
                    .map { cell in
                        var cell = cell
                        cell.width = 1
                        return cell
                    }
            }
            let firstRow = result.count
            var rowStarts = [0]
            var used = 0
            for offset in cells.indices {
                let cell = cells[offset]
                let isInTab = cell.isTabGap && offset > 0 && (cells[offset - 1].isTab || cells[offset - 1].isTabGap)
                let width = cell.isTab ? cells[(offset + 1)...].prefix(while: \.isTabGap).count + 1 : Int(cell.width)
                if !isInTab, width > 0, used > 0, used + width > columns {
                    var line = Line(cells[rowStarts[rowStarts.count - 1] ..< offset], isWrapped: true)
                    line.writeSkippedCellsAtEnd()
                    line.append(contentsOf: repeatElement(.padding, count: max(columns - used, 0)))
                    result.append(line)
                    rowStarts.append(offset)
                    used = 0
                }
                used += Int(cell.width)
            }
            let lastStart = rowStarts[rowStarts.count - 1]
            let keepsEmptyRow = textCount == 0 && used == columns
            var lastLine = Line(cells[lastStart...], isWrapped: keepsEmptyRow || lines[end].isWrapped)
            if let fill = lines[end].fill, used < columns {
                lastLine.append(fill)
            }
            result.append(lastLine)
            if keepsEmptyRow {
                result.append(Line([], isWrapped: lines[end].isWrapped))
            }
            let rowCount = rowStarts.count + (keepsEmptyRow ? 1 : 0)
            guard let cursorOffset else {
                continue
            }
            if isPastEnd {
                reflowedCursor = Position(row: firstRow + rowCount, column: 0)
            } else if keepsEmptyRow, cursorOffset == cells.count {
                reflowedCursor = Position(row: firstRow + rowCount - 1, column: 0)
            } else if cursorOffset < cells.count {
                let row = rowStarts.lastIndex { $0 <= cursorOffset } ?? 0
                reflowedCursor = Position(row: firstRow + row, column: cursorOffset - rowStarts[row])
            } else {
                reflowedCursor = Position(
                    row: firstRow + rowStarts.count - 1,
                    column: min(cursorOffset - lastStart, columns - 1)
                )
            }
        }
        return (result, reflowedCursor)
    }
}
