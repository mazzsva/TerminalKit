extension Terminal {
    package struct Line: Equatable, Sendable, RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
        package var isWrapped = false
        private var cells: [Cell]

        package init() {
            cells = []
        }

        init(_ cells: some Sequence<Cell>, isWrapped: Bool = false) {
            self.cells = Array(cells)
            self.isWrapped = isWrapped
        }

        package var startIndex: Int {
            cells.startIndex
        }

        package var endIndex: Int {
            cells.endIndex
        }

        package subscript(position: Int) -> Cell {
            get { cells[position] }
            set { cells[position] = newValue }
        }

        package mutating func replaceSubrange(_ subrange: Range<Int>, with newElements: some Collection<Cell>) {
            cells.replaceSubrange(subrange, with: newElements)
        }

        package mutating func append(_ cell: Cell) {
            cells.append(cell)
        }

        package mutating func append(contentsOf newElements: some Sequence<Cell>) {
            cells.append(contentsOf: newElements)
        }

        package mutating func reserveCapacity(_ capacity: Int) {
            cells.reserveCapacity(capacity)
        }

        package func withContiguousStorageIfAvailable<Result>(
            _ body: (UnsafeBufferPointer<Cell>) throws -> Result
        ) rethrows -> Result? {
            try cells.withContiguousStorageIfAvailable(body)
        }
    }
}
