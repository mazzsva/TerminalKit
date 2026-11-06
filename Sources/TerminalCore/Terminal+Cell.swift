extension Terminal {
    package struct Cell: Equatable, Sendable {
        package static let padding = Cell(scalar: "\u{0}")
        fileprivate static let firstGraphemeIndex: UInt32 = 0x11_0000
        fileprivate static let writtenSpaceContent: UInt32 = 0x7F
        fileprivate static let tabContent: UInt32 = 0x9
        fileprivate static let tabGapContent: UInt32 = 0xB

        package var style = Style()
        package var width: UInt8 = 1
        fileprivate var content: UInt32 = 0x20

        package init(scalar: Unicode.Scalar = " ", style: Style = Style(), width: UInt8 = 1) {
            self.style = style
            self.width = width
            content = scalar.value
        }

        package static func writtenSpace(style: Style = Style()) -> Cell {
            var cell = Cell(style: style)
            cell.content = writtenSpaceContent
            return cell
        }

        static func tab(style: Style) -> Cell {
            var cell = Cell(style: style)
            cell.content = tabContent
            return cell
        }

        static func tabGap(style: Style) -> Cell {
            var cell = Cell(style: style)
            cell.content = tabGapContent
            return cell
        }

        var isTab: Bool {
            content == Self.tabContent
        }

        package var isTabGap: Bool {
            content == Self.tabGapContent
        }

        package var isWritten: Bool {
            content != 0x20 && content != 0 && content != Self.tabGapContent
        }

        package var isText: Bool {
            width > 0 && self != .padding && content != Self.tabGapContent
        }

        package var isBlank: Bool {
            self == Cell() || self == .padding
        }

        package var isSpace: Bool {
            content == 0x20 || content == 0 || content == Self.writtenSpaceContent || isTab || isTabGap
        }

        package var isASCII: Bool {
            content < 0x80
        }

        fileprivate var graphemeIndex: Int? {
            content >= Self.firstGraphemeIndex ? Int(content - Self.firstGraphemeIndex) : nil
        }
    }

    package struct Graphemes: Sendable {
        let capacity: Int
        private var characters: [String] = []
        private var indices: [[UInt8]: UInt32] = [:]
        private var additionsSinceCompaction = 0
        private var compactionInterval: Int

        init(capacity: Int = 65_536) {
            self.capacity = capacity
            compactionInterval = max(capacity / 64, 1)
        }

        var count: Int {
            characters.count
        }

        package func character(of cell: Cell) -> String {
            guard let index = cell.graphemeIndex else {
                if cell.isTab {
                    return "\t"
                }
                return cell.isSpace ? " " : Unicode.Scalar(cell.content).map(String.init) ?? " "
            }
            return characters[index]
        }

        mutating func resetCompactionInterval() {
            compactionInterval = max(capacity / 64, 1)
        }

        func needsCompaction(for character: String) -> Bool {
            characters.count >= capacity && additionsSinceCompaction >= compactionInterval
                && !character.unicodeScalars.dropFirst().isEmpty && indices[Array(character.utf8)] == nil
        }

        mutating func cell(_ cell: Cell, with character: String) -> Cell {
            var cell = cell
            let scalars = character.unicodeScalars
            if let scalar = scalars.first, scalars.dropFirst().isEmpty {
                cell.content = scalar.value
            } else if let index = index(of: character) {
                cell.content = Cell.firstGraphemeIndex + index
            }
            return cell
        }

        static func markIndices(in lines: [Line], into used: inout [Bool]) {
            for line in lines {
                for cell in line {
                    if let index = cell.graphemeIndex {
                        used[index] = true
                    }
                }
            }
        }

        mutating func compact(keeping used: [Bool]) -> [UInt32] {
            var newIndices = Array(repeating: UInt32(0), count: characters.count)
            var kept: [String] = []
            for (index, character) in characters.enumerated() where used[index] {
                newIndices[index] = UInt32(kept.count)
                kept.append(character)
            }
            if kept.count < characters.count - kept.count {
                indices.removeAll(keepingCapacity: true)
                for (index, character) in kept.enumerated() {
                    indices[Array(character.utf8)] = UInt32(index)
                }
            } else {
                for (index, character) in characters.enumerated() where !used[index] {
                    indices[Array(character.utf8)] = nil
                }
                indices = indices.mapValues { newIndices[Int($0)] }
            }
            compactionInterval =
                kept.count > characters.count * 3 / 4 ? min(compactionInterval * 2, capacity) : max(capacity / 64, 1)
            characters = kept
            additionsSinceCompaction = 0
            return newIndices
        }

        static func remapIndices(in lines: inout [Line], with newIndices: [UInt32]) {
            for row in lines.indices where lines[row].contains(where: { $0.graphemeIndex != nil }) {
                for column in lines[row].indices {
                    if let index = lines[row][column].graphemeIndex {
                        lines[row][column].content = Cell.firstGraphemeIndex + newIndices[index]
                    }
                }
            }
        }

        private mutating func index(of character: String) -> UInt32? {
            if let index = indices[Array(character.utf8)] {
                return index
            }
            additionsSinceCompaction += 1
            guard characters.count < capacity else {
                return nil
            }
            let index = UInt32(characters.count)
            characters.append(character)
            indices[Array(character.utf8)] = index
            return index
        }
    }
}
