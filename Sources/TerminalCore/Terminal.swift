package struct Terminal: Sendable {
    package struct Cell: Equatable, Sendable {
        package var character: Character = " "
    }

    package struct Position: Equatable, Sendable {
        package var row: Int
        package var column: Int
    }

    private static let tabWidth = 8

    package let columns: Int
    package let rows: Int
    package private(set) var screen: [[Cell]]
    package private(set) var cursor = Position(row: 0, column: 0)

    private var decoder = UTF8Decoder()
    private var parser = EscapeSequenceParser()
    private var isWrapPending = false

    package init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        screen = Array(repeating: Self.blankLine(columns: columns), count: rows)
    }

    package mutating func receive(_ bytes: some Sequence<UInt8>) {
        for action in parser.parse(decoder.decode(bytes)) {
            switch action {
            case .print(let scalar):
                print(Character(scalar))
            case .execute("\n"):
                lineFeed()
            case .execute("\r"):
                carriageReturn()
            case .execute("\u{8}"):
                moveCursor(row: cursor.row, column: cursor.column - 1)
            case .execute("\t"):
                cursor.column = min((cursor.column / Self.tabWidth + 1) * Self.tabWidth, columns - 1)
            case .controlSequence(let sequence):
                perform(sequence)
            default:
                break
            }
        }
    }

    private mutating func perform(_ sequence: EscapeSequenceParser.ControlSequence) {
        guard sequence.privateMarker == nil, sequence.intermediates.isEmpty else {
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
            moveCursor(row: cursor.row, column: cursor.column - count)
        case "E":
            moveCursor(row: cursor.row + count, column: 0)
        case "F":
            moveCursor(row: cursor.row - count, column: 0)
        case "G":
            moveCursor(row: cursor.row, column: count - 1)
        case "H", "f":
            moveCursor(row: count - 1, column: sequence.parameter(at: 1, default: 1) - 1)
        case "d":
            moveCursor(row: count - 1, column: cursor.column)
        case "K":
            eraseInLine(sequence.parameter(at: 0, default: 0))
        default:
            break
        }
    }

    private mutating func print(_ character: Character) {
        if isWrapPending {
            carriageReturn()
            lineFeed()
        }
        screen[cursor.row][cursor.column].character = character
        if cursor.column == columns - 1 {
            isWrapPending = true
        } else {
            cursor.column += 1
        }
    }

    private mutating func lineFeed() {
        isWrapPending = false
        if cursor.row == rows - 1 {
            screen.removeFirst()
            screen.append(Self.blankLine(columns: columns))
        } else {
            cursor.row += 1
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
        screen[row].replaceSubrange(range, with: repeatElement(Cell(), count: range.count))
    }

    private static func blankLine(columns: Int) -> [Cell] {
        Array(repeating: Cell(), count: columns)
    }
}
