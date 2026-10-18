extension Terminal {
    static func reflow(_ lines: [Line], columns: Int, positions: [Position]) -> (lines: [Line], positions: [Position]) {
        var result: [Line] = []
        result.reserveCapacity(lines.count)
        var newPositions = positions
        let positionsByRow = Dictionary(grouping: positions.indices) { positions[$0].row }
        var start = 0
        while start < lines.count {
            var end = start
            while end < lines.count - 1, lines[end].isWrapped {
                end += 1
            }
            defer { start = end + 1 }
            let trimmedCount = (lines[end].lastIndex { !$0.isBlank } ?? -1) + 1
            if start == end, trimmedCount <= columns {
                let line = lines[start]
                result.append(
                    trimmedCount == line.count ? line : Line(line.prefix(trimmedCount), isWrapped: line.isWrapped)
                )
                for index in positionsByRow[start] ?? [] {
                    newPositions[index] = Position(
                        row: result.count - 1, column: min(positions[index].column, columns - 1))
                }
                continue
            }

            var cells: [Cell] = []
            var offsets: [(offset: Int, index: Int)] = []
            for row in start ... end {
                var rowCells = lines[row][...]
                if row < end, rowCells.last == .padding {
                    rowCells = rowCells.dropLast()
                } else if row == end {
                    rowCells = rowCells.prefix(trimmedCount)
                }
                for index in positionsByRow[row] ?? [] {
                    offsets.append((cells.count + positions[index].column, index))
                }
                cells.append(contentsOf: rowCells)
            }
            if columns == 1 {
                offsets = offsets.map { offset, index in
                    let kept = cells[..<min(offset, cells.count)].count { $0.width > 0 }
                    guard offset < cells.count else {
                        return (kept + offset - cells.count, index)
                    }
                    return (cells[offset].width == 0 ? kept - 1 : kept, index)
                }
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
                let width = Int(cells[offset].width)
                if width > 0, used + width > columns {
                    var line = Line(cells[rowStarts[rowStarts.count - 1] ..< offset], isWrapped: true)
                    line.append(contentsOf: repeatElement(.padding, count: columns - used))
                    result.append(line)
                    rowStarts.append(offset)
                    used = 0
                }
                used += width
            }
            let lastStart = rowStarts[rowStarts.count - 1]
            result.append(Line(cells[lastStart...], isWrapped: lines[end].isWrapped))

            for (offset, index) in offsets {
                if offset < cells.count {
                    let row = rowStarts.lastIndex { $0 <= offset } ?? 0
                    newPositions[index] = Position(row: firstRow + row, column: offset - rowStarts[row])
                } else {
                    newPositions[index] = Position(
                        row: firstRow + rowStarts.count - 1,
                        column: min(offset - lastStart, columns - 1)
                    )
                }
            }
        }
        return (result, newPositions)
    }
}
