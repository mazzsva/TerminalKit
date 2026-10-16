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

    package init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        screen = Array(repeating: Array(repeating: Cell(), count: columns), count: rows)
    }

    package mutating func receive(_ bytes: some Sequence<UInt8>) {
        for action in parser.parse(decoder.decode(bytes)) {
            switch action {
            case .print(let scalar):
                print(Character(scalar))
            default:
                break
            }
        }
    }

    private mutating func print(_ character: Character) {
        screen[cursor.row][cursor.column].character = character
        cursor.column = min(cursor.column + 1, columns - 1)
    }
}
