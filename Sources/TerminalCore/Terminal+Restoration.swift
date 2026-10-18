import Foundation

extension Terminal {
    package struct Restoration: Codable, Equatable, Sendable {
        package var columns: Int
        package var rows: Int
        package var content: Data
        package var commands: [Command]
        package var removedCommandCount: Int
        package var currentDirectory: URL?
    }

    private static let maximumRestoredSize = 1_000
    private static let maximumRemovedCommandCount = 1 << 40

    package var restoration: Restoration {
        let firstRow = removedScrollbackCount
        var lines = scrollback + normalLines
        let cursorRow = scrollback.count + normalCursor.row
        if let mark = prompt ?? input, lines.indices.contains(mark.row - firstRow),
            cursorRow <= mark.row - firstRow || !lines[cursorRow].allSatisfy(\.isBlank)
                || lines[cursorRow - 1].isWrapped
        {
            let row = mark.row - firstRow
            var column = mark.column
            if lines[row].indices.contains(column), lines[row][column].width == 0 {
                column += 1
            }
            if mark.column == columns - 1,
                lines[row].isWrapped || row == cursorRow && mark.column == normalCursor.column && isNormalWrapPending
            {
                column = columns
            }
            lines[row] = Line(lines[row].prefix(column))
            lines.removeSubrange(row + 1 ..< lines.count)
        }
        var commands = commands
        for index in commands.indices {
            for keyPath in [\Command.prompt, \.output, \.end] {
                commands[index][keyPath: keyPath]?.row -= firstRow
            }
        }
        return Restoration(
            columns: columns,
            rows: rows,
            content: Data(content(of: lines).utf8),
            commands: commands,
            removedCommandCount: removedCommandCount,
            currentDirectory: currentDirectory
        )
    }

    package init(restoring restoration: Restoration) {
        self.init(
            columns: min(max(restoration.columns, 1), Self.maximumRestoredSize),
            rows: min(max(restoration.rows, 1), Self.maximumRestoredSize),
            replaying: Array(restoration.content)
        )
        let firstRow = removedScrollbackCount
        let lastColumn = columns - 1
        let end = Position(row: removedScrollbackCount + scrollback.count + cursor.row, column: cursor.column)
        commands = Array(restoration.commands.suffix(Self.maximumCommands))
        removedCommandCount =
            min(max(restoration.removedCommandCount, 0), Self.maximumRemovedCommandCount)
            + restoration.commands.count - commands.count
        updateMarks { position in
            guard let mark = position else {
                return
            }
            if mark.row < firstRow {
                position = nil
            } else if mark.row > end.row || mark.row == end.row && mark.column > end.column {
                position = end
            } else {
                position?.column = min(max(mark.column, 0), lastColumn)
            }
        }
        for index in commands.indices {
            if !commands[index].isFinished {
                commands[index].isFinished = true
                commands[index].end = commands[index].end ?? end
            }
            if commands[index].directory?.isFileURL == false {
                commands[index].directory = nil
            }
        }
        if let directory = restoration.currentDirectory, directory.isFileURL {
            currentDirectory = directory
        }
    }

    private struct EmittedCell {
        var character: Character
        var style: Style
        var width: Int

        var isBlank: Bool {
            character == " " && style == Style()
        }
    }

    private func emittedCells(of line: Line) -> [EmittedCell] {
        var cells: [EmittedCell] = []
        var column = 0
        let end = min(line.count, columns)
        while column < end {
            let cell = line[column]
            let isWide = cell.width == 2 && column + 1 < end && line[column + 1].width == 0
            cells.append(
                EmittedCell(
                    character: cell.width == 1 || isWide ? character(of: cell) : " ",
                    style: cell.style,
                    width: isWide ? 2 : 1
                )
            )
            column += isWide ? 2 : 1
        }
        return cells
    }

    private func content(of lines: [Line]) -> String {
        let rows = lines.map(emittedCells)
        var count = rows.count
        while count > 0, rows[count - 1].allSatisfy(\.isBlank) {
            count -= 1
        }
        var counts = Array(repeating: 0, count: count)
        var continues = Array(repeating: false, count: count)
        for index in (0 ..< count).reversed() {
            let line = lines[index]
            let endsInPadding = line.count == columns && line.last == .padding
            continues[index] =
                line.isWrapped && line.count == columns && index + 1 < count
                && (!endsInPadding || rows[index + 1].first?.width == 2)
            if continues[index] {
                counts[index] = rows[index].count - (endsInPadding ? 1 : 0)
            } else {
                counts[index] = (rows[index].lastIndex { !$0.isBlank } ?? -1) + 1
            }
        }
        var content = ""
        var style = Style()
        for index in 0 ..< count {
            for cell in rows[index].prefix(counts[index]) {
                if cell.style != style {
                    content += controls(from: style, to: cell.style)
                    style = cell.style
                }
                content.append(cell.character)
            }
            content += controls(from: style, to: Style())
            style = Style()
            if continues[index] {
                if counts[index + 1] == 0 {
                    content += " "
                } else if lines[index].last == .padding {
                    content += "\u{1B}[K"
                }
                continue
            }
            if index > 0, continues[index - 1], rows[index].prefix(counts[index]).reduce(0, { $0 + $1.width }) < columns
            {
                content += "\u{1B}[K"
            }
            content += "\r\n"
        }
        return content
    }

    private func controls(from old: Style, to new: Style) -> String {
        var content = ""
        var oldAppearance = old
        var newAppearance = new
        oldAppearance.link = 0
        newAppearance.link = 0
        if oldAppearance != newAppearance {
            var parameters = [0]
            for (isOn, parameter) in [
                (new.isBold, 1), (new.isFaint, 2), (new.isItalic, 3), (new.isUnderlined, 4),
                (new.isInverse, 7), (new.isHidden, 8), (new.isStrikethrough, 9),
            ] where isOn {
                parameters.append(parameter)
            }
            parameters += Self.parameters(of: new.foreground, base: 38)
            parameters += Self.parameters(of: new.background, base: 48)
            content += "\u{1B}[\(parameters.map(String.init).joined(separator: ";"))m"
        }
        if old.link != new.link {
            content += "\u{1B}]8;;\(links.uri(of: new.link) ?? "")\u{1B}\\"
        }
        return content
    }

    private static func parameters(of color: Color, base: Int) -> [Int] {
        switch color {
        case .default:
            []
        case .indexed(let index):
            [base, 5, Int(index)]
        case .rgb(let red, let green, let blue):
            [base, 2, Int(red), Int(green), Int(blue)]
        }
    }
}
