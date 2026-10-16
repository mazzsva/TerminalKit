package struct Terminal: Sendable {
    package struct Cell: Equatable, Sendable {
        package var character: Character = " "
    }

    package struct Position: Equatable, Sendable {
        package var row: Int
        package var column: Int
    }

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
            default:
                break
            }
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

    private static func blankLine(columns: Int) -> [Cell] {
        Array(repeating: Cell(), count: columns)
    }
}
