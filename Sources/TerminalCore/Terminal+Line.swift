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
    }
}
