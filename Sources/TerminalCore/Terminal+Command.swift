import Foundation

extension Terminal {
    package struct Command: Equatable, Sendable {
        package var text: String?
        package var directory: URL?
        package var prompt: Position?
        package var output: Position?
        package var end: Position?
        package var exitStatus: Int32?
        package var isFinished = false
    }

    private static let maximumCommands = 10_000
    private static let commandTrimCount = 1_000

    mutating func performShellIntegration(_ mark: Substring) {
        let parameters = mark.split(separator: ";", omittingEmptySubsequences: false)
        switch parameters[0] {
        case "A":
            finishCommand(exitStatus: nil)
            prompt = markPosition
            input = nil
        case "B":
            input = markPosition
        case "C":
            finishCommand(exitStatus: nil)
            let text =
                parameters.dropFirst()
                .first { $0.hasPrefix("cmdline_url=") }
                .flatMap { $0.dropFirst("cmdline_url=".count).removingPercentEncoding }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? inputText
            commands.append(
                Command(text: text, directory: currentDirectory, prompt: prompt ?? input, output: markPosition)
            )
            prompt = nil
            input = nil
            if commands.count > Self.maximumCommands + Self.commandTrimCount {
                removedCommandCount += commands.count - Self.maximumCommands
                commands.removeFirst(commands.count - Self.maximumCommands)
            }
        case "D":
            finishCommand(exitStatus: parameters.count > 1 ? Int32(parameters[1]) : nil)
        default:
            break
        }
    }

    mutating func setCurrentDirectory(_ location: Substring) {
        guard let url = URL(string: String(location)), url.isFileURL else {
            return
        }
        currentDirectory = url
    }

    mutating func updateMarks(_ update: (inout Position?) -> Void) {
        update(&prompt)
        update(&input)
        for index in commands.indices {
            update(&commands[index].prompt)
            update(&commands[index].output)
            update(&commands[index].end)
        }
    }

    mutating func forgetMarks(after row: Int) {
        let firstRow = removedScrollbackCount + scrollback.count + row + 1
        updateMarks { position in
            if let row = position?.row, row >= firstRow {
                position = nil
            }
        }
    }

    private var markPosition: Position? {
        guard !isAlternateScreenActive else {
            return nil
        }
        return Position(row: removedScrollbackCount + scrollback.count + cursor.row, column: cursor.column)
    }

    private var inputText: String? {
        guard let input, let end = markPosition, input.row <= end.row else {
            return nil
        }
        var text = ""
        for row in input.row ... end.row {
            guard let line = line(atMark: row) else {
                return nil
            }
            let start = row == input.row ? min(input.column, line.count) : 0
            let cells = line[start ..< (row == end.row ? max(min(end.column, line.count), start) : line.count)]
            let isWrapped = line.isWrapped && row < end.row
            let stop = isWrapped ? cells.endIndex : (cells.lastIndex { !$0.isBlank }).map { $0 + 1 } ?? start
            text += String(cells[start ..< stop].filter { $0.width > 0 && $0 != .padding }.map(\.character))
            if !isWrapped, row < end.row {
                text += "\n"
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func line(atMark row: Int) -> Line? {
        let index = row - removedScrollbackCount
        guard index >= 0 else {
            return nil
        }
        guard index >= scrollback.count else {
            return scrollback[index]
        }
        return screen.indices.contains(index - scrollback.count) ? screen[index - scrollback.count] : nil
    }

    private mutating func finishCommand(exitStatus: Int32?) {
        guard let last = commands.indices.last, !commands[last].isFinished else {
            return
        }
        commands[last].isFinished = true
        commands[last].exitStatus = exitStatus
        commands[last].end = markPosition
    }
}
