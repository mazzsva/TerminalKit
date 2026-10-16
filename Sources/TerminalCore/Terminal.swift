package struct Terminal: Sendable {
    package struct Cell: Equatable, Sendable {
        package var character: Character = " "
    }

    package let columns: Int
    package let rows: Int
    package private(set) var screen: [[Cell]]

    package init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0)
        self.columns = columns
        self.rows = rows
        screen = Array(repeating: Array(repeating: Cell(), count: columns), count: rows)
    }
}
