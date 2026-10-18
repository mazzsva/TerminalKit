import Synchronization

extension Terminal {
    package struct Cell: Equatable, Sendable {
        package static let padding = Cell(scalar: "\u{0}")
        private static let firstGraphemeIndex: UInt32 = 0x11_0000

        package var style = Style()
        package var width: UInt8 = 1
        private var content: UInt32 = 0x20

        package init(scalar: Unicode.Scalar = " ", style: Style = Style(), width: UInt8 = 1) {
            self.style = style
            self.width = width
            content = scalar.value
        }

        package var isBlank: Bool {
            self == Cell() || self == .padding
        }

        package var character: Character {
            get {
                guard content >= Self.firstGraphemeIndex else {
                    return content == 0 ? " " : Unicode.Scalar(content).map(Character.init) ?? " "
                }
                return graphemes.withLock { $0.characters[Int(content - Self.firstGraphemeIndex)] }
            }
            set {
                let scalars = newValue.unicodeScalars
                if scalars.count > 1, let index = graphemes.withLock({ $0.index(of: newValue) }) {
                    content = Self.firstGraphemeIndex + index
                } else if let scalar = scalars.first {
                    content = scalar.value
                }
            }
        }
    }
}

private let graphemes = Mutex(Graphemes())

private struct Graphemes {
    static let capacity = 65_536

    var characters: [Character] = []
    var indices: [Character: UInt32] = [:]

    mutating func index(of character: Character) -> UInt32? {
        if let index = indices[character] {
            return index
        }
        guard characters.count < Self.capacity else {
            return nil
        }
        let index = UInt32(characters.count)
        characters.append(character)
        indices[character] = index
        return index
    }
}
