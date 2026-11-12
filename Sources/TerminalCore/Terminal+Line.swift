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

        var fill: Cell? {
            last.flatMap { !$0.isContent && !$0.isBlank ? $0 : nil }
        }

        var textCount: Int {
            (lastIndex(where: \.isContent) ?? -1) + 1
        }

        package func columnCount(at column: Int) -> Int {
            guard self[column].isTab else {
                return Swift.max(Int(self[column].width), 1)
            }
            return (self[(column + 1)...].firstIndex { !$0.isTabGap } ?? count) - column
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
