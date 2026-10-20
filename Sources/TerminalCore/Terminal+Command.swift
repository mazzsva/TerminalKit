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
    private static let maximumTextLength = 4_096
    private static let commandTrimCount = 1_000

    mutating func performShellIntegration(_ mark: Substring) {
        let parameters = mark.split(separator: ";", omittingEmptySubsequences: false)
        if let nonce = shellIntegrationNonce, !parameters.contains(where: { $0 == "nonce=\(nonce)" }) {
            return
        }
        switch parameters[0] {
        case "A":
            if !parameters.contains("k=s") {
                finishCommand(exitStatus: nil)
                prompt = markPosition
                input = nil
            }
            redrawnPrompt = markPosition
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
            redrawnPrompt = nil
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

    private static let launchHostName = currentHostName

    private static var currentHostName: String {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&name, Int(MAXHOSTNAMELEN)) == 0 else {
            return ""
        }
        return String(decoding: name.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self).lowercased()
    }

    mutating func setCurrentDirectory(_ location: Substring) {
        guard let url = URL(string: String(location)), url.isFileURL else {
            return
        }
        let path = url.path(percentEncoded: false)
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        guard ["", "localhost", Self.launchHostName, Self.currentHostName].contains(host), path.hasPrefix("/") else {
            currentDirectory = nil
            return
        }
        currentDirectory = URL(filePath: path)
    }

    mutating func updateMarks(_ update: (inout Position?) -> Void) {
        update(&prompt)
        update(&input)
        update(&redrawnPrompt)
        for index in commands.indices {
            update(&commands[index].prompt)
            update(&commands[index].output)
            update(&commands[index].end)
        }
    }

    mutating func forgetMarks(after row: Int) {
        let firstRow = removedScrollbackCount + scrollback.count + row + 1
        func forget(_ position: inout Position?) {
            if let row = position?.row, row >= firstRow {
                position = nil
            }
        }
        forget(&prompt)
        forget(&input)
        forget(&redrawnPrompt)
        for index in commands.indices.reversed() {
            let isBefore = [commands[index].prompt, commands[index].output, commands[index].end]
                .contains { $0.map { $0.row < firstRow } == true }
            forget(&commands[index].prompt)
            forget(&commands[index].output)
            forget(&commands[index].end)
            if isBefore {
                break
            }
        }
    }

    private var markPosition: Position? {
        guard !isAlternateScreenActive else {
            return nil
        }
        return Position(row: removedScrollbackCount + scrollback.count + cursor.row, column: cursor.column)
    }

    package func output(ofCommandAt index: Int) -> String? {
        guard commands.indices.contains(index), let output = commands[index].output else {
            return nil
        }
        let cursor = Position(
            row: removedScrollbackCount + scrollback.count + normalCursor.row, column: normalCursor.column)
        return text(from: output, to: commands[index].end ?? cursor)
    }

    private var inputText: String? {
        guard let input, let end = markPosition,
            let text = text(from: input, to: end, limit: Self.maximumTextLength)
        else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength)
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    private func text(from start: Position, to end: Position, limit: Int = .max) -> String? {
        guard start.row <= end.row else {
            return nil
        }
        var text = ""
        var length = 0
        for row in start.row ... end.row {
            guard let line = line(atMark: row) else {
                return nil
            }
            let first = row == start.row ? min(start.column, line.count) : 0
            let cells = line[first ..< (row == end.row ? max(min(end.column, line.count), first) : line.count)]
            let isWrapped = line.isWrapped && row < end.row
            let stop = isWrapped ? cells.endIndex : (cells.lastIndex { !$0.isBlank }).map { $0 + 1 } ?? first
            let piece = cells[first ..< stop].filter { $0.width > 0 && $0 != .padding }.map(graphemes.character(of:))
            text += String(piece)
            length += piece.count
            if !isWrapped, row < end.row {
                text += "\n"
                length += 1
            }
            if length > limit {
                break
            }
        }
        return text
    }

    private func line(atMark row: Int) -> Line? {
        let index = row - removedScrollbackCount
        guard index >= 0 else {
            return nil
        }
        guard index >= scrollback.count else {
            return scrollback[index]
        }
        let lines = normalLines
        return lines.indices.contains(index - scrollback.count) ? lines[index - scrollback.count] : nil
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
