extension Terminal {
    package struct Cell: Equatable, Sendable {
        package static let padding = Cell(scalar: "\u{0}")
        fileprivate static let firstGraphemeIndex: UInt32 = 0x11_0000

        package var style = Style()
        package var width: UInt8 = 1
        fileprivate var content: UInt32 = 0x20

        package init(scalar: Unicode.Scalar = " ", style: Style = Style(), width: UInt8 = 1) {
            self.style = style
            self.width = width
            content = scalar.value
        }

        package var isBlank: Bool {
            self == Cell() || self == .padding
        }

        package var isSpace: Bool {
            content == 0x20 || content == 0
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
        private var characters: [Character] = []
        private var indices: [Character: UInt32] = [:]
        private var additionsSinceCompaction = 0
        private var compactionInterval: Int

        init(capacity: Int = 65_536) {
            self.capacity = capacity
            compactionInterval = max(capacity / 64, 1)
        }

        var count: Int {
            characters.count
        }

        package func character(of cell: Cell) -> Character {
            guard let index = cell.graphemeIndex else {
                return cell.content == 0 ? " " : Unicode.Scalar(cell.content).map(Character.init) ?? " "
            }
            return characters[index]
        }

        mutating func resetCompactionInterval() {
            compactionInterval = max(capacity / 64, 1)
        }

        func needsCompaction(for character: Character) -> Bool {
            characters.count >= capacity && additionsSinceCompaction >= compactionInterval
                && character.unicodeScalars.count > 1 && indices[character] == nil
        }

        mutating func cell(_ cell: Cell, with character: Character) -> Cell {
            var cell = cell
            let scalars = character.unicodeScalars
            if scalars.count == 1, let scalar = scalars.first {
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
            var kept: [Character] = []
            for (index, character) in characters.enumerated() where used[index] {
                newIndices[index] = UInt32(kept.count)
                kept.append(character)
            }
            compactionInterval =
                kept.count > characters.count * 3 / 4 ? min(compactionInterval * 2, capacity) : max(capacity / 64, 1)
            characters = kept
            indices = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1, UInt32($0)) })
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

        private mutating func index(of character: Character) -> UInt32? {
            if let index = indices[character] {
                return index
            }
            additionsSinceCompaction += 1
            guard characters.count < capacity else {
                return nil
            }
            let index = UInt32(characters.count)
            characters.append(character)
            indices[character] = index
            return index
        }
    }
}
