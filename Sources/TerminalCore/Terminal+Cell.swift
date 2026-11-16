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

        var isContent: Bool {
            isWritten || isTabGap || width == 0
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
        private static let maximumCount = 65_536

        private var characters: [String] = []
        private var indices: [[UInt8]: UInt32] = [:]
        private var requestCount = 0
        private var rebuildRequestCount = 0
        private var unsharedIndex: Int?

        var isEmpty: Bool {
            characters.isEmpty
        }

        var needsRebuild: Bool {
            characters.count >= Self.maximumCount && requestCount >= rebuildRequestCount
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

        mutating func cell(_ cell: Cell, with character: String) -> Cell {
            var cell = cell
            if let index = indices[Array(character.utf8)] {
                if Int(index) == unsharedIndex {
                    unsharedIndex = nil
                }
                cell.content = Cell.firstGraphemeIndex + index
                return cell
            }
            if let index = cell.graphemeIndex, index == unsharedIndex {
                indices[Array(characters[index].utf8)] = nil
                characters[index] = character
                indices[Array(character.utf8)] = UInt32(index)
                return cell
            }
            requestCount += 1
            guard characters.count < Self.maximumCount else {
                return cell
            }
            cell.content = Cell.firstGraphemeIndex + append(character)
            unsharedIndex = cell.graphemeIndex
            return cell
        }

        mutating func shareCharacters() {
            unsharedIndex = nil
        }

        mutating func move(_ line: inout Line, from graphemes: Graphemes) {
            for column in line.indices {
                if let index = line[column].graphemeIndex {
                    let character = graphemes.characters[index]
                    let newIndex = indices[Array(character.utf8)] ?? append(character)
                    line[column].content = Cell.firstGraphemeIndex + newIndex
                }
            }
        }

        mutating func endRebuild() {
            requestCount = 0
            rebuildRequestCount = characters.count
        }

        private mutating func append(_ character: String) -> UInt32 {
            let index = UInt32(characters.count)
            characters.append(character)
            indices[Array(character.utf8)] = index
            return index
        }
    }
}
