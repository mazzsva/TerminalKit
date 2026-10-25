extension Terminal {
    package enum Color: Hashable, Sendable {
        case `default`
        case indexed(UInt8)
        case rgb(red: UInt8, green: UInt8, blue: UInt8)
    }

    package struct Style: Equatable, Sendable {
        package var foreground = Color.default
        package var background = Color.default
        package var link: UInt16 = 0
        private var flags: UInt8 = 0

        package init(
            foreground: Color = .default,
            background: Color = .default,
            link: UInt16 = 0,
            isBold: Bool = false,
            isFaint: Bool = false,
            isItalic: Bool = false,
            isUnderlined: Bool = false,
            isInverse: Bool = false,
            isHidden: Bool = false,
            isStrikethrough: Bool = false
        ) {
            self.foreground = foreground
            self.background = background
            self.link = link
            self.isBold = isBold
            self.isFaint = isFaint
            self.isItalic = isItalic
            self.isUnderlined = isUnderlined
            self.isInverse = isInverse
            self.isHidden = isHidden
            self.isStrikethrough = isStrikethrough
        }

        package var isBold: Bool {
            get { flag(0) }
            set { setFlag(0, newValue) }
        }

        package var isFaint: Bool {
            get { flag(1) }
            set { setFlag(1, newValue) }
        }

        package var isItalic: Bool {
            get { flag(2) }
            set { setFlag(2, newValue) }
        }

        package var isUnderlined: Bool {
            get { flag(3) }
            set { setFlag(3, newValue) }
        }

        package var isInverse: Bool {
            get { flag(4) }
            set { setFlag(4, newValue) }
        }

        package var isHidden: Bool {
            get { flag(5) }
            set { setFlag(5, newValue) }
        }

        package var isStrikethrough: Bool {
            get { flag(6) }
            set { setFlag(6, newValue) }
        }

        private func flag(_ bit: UInt8) -> Bool {
            flags & 1 << bit != 0
        }

        private mutating func setFlag(_ bit: UInt8, _ isOn: Bool) {
            flags = isOn ? flags | 1 << bit : flags & ~(1 << bit)
        }

        mutating func apply(_ parameters: [Int], subparameters: Set<Int> = []) {
            var parameters = (parameters.isEmpty ? [0] : Self.parameters(parameters, grouping: subparameters))
                .makeIterator()
            while let parameter = parameters.next() {
                switch parameter {
                case 0:
                    self = Style(link: link)
                case 1:
                    isBold = true
                case 2:
                    isFaint = true
                case 3:
                    isItalic = true
                case 4, 21:
                    isUnderlined = true
                case 7:
                    isInverse = true
                case 8:
                    isHidden = true
                case 9:
                    isStrikethrough = true
                case 22:
                    isBold = false
                    isFaint = false
                case 23:
                    isItalic = false
                case 24:
                    isUnderlined = false
                case 27:
                    isInverse = false
                case 28:
                    isHidden = false
                case 29:
                    isStrikethrough = false
                case 30 ... 37:
                    foreground = .indexed(UInt8(parameter - 30))
                case 38:
                    foreground = Self.color(from: &parameters) ?? foreground
                case 39:
                    foreground = .default
                case 40 ... 47:
                    background = .indexed(UInt8(parameter - 40))
                case 48:
                    background = Self.color(from: &parameters) ?? background
                case 49:
                    background = .default
                case 58:
                    _ = Self.color(from: &parameters)
                case 90 ... 97:
                    foreground = .indexed(UInt8(parameter - 82))
                case 100 ... 107:
                    background = .indexed(UInt8(parameter - 92))
                default:
                    break
                }
            }
        }

        private static func parameters(_ parameters: [Int], grouping subparameters: Set<Int>) -> [Int] {
            guard !subparameters.isEmpty else {
                return parameters
            }
            var groups: [[Int]] = []
            for (index, parameter) in parameters.enumerated() {
                if subparameters.contains(index) {
                    groups[groups.count - 1].append(parameter)
                } else {
                    groups.append([parameter])
                }
            }
            return groups.flatMap { $0.count == 1 ? $0 : Self.parameters(fromSubparameters: $0) }
        }

        private static func parameters(fromSubparameters group: [Int]) -> [Int] {
            switch (group[0], group[1], group.count) {
            case (4, 0, 2):
                [24]
            case (4, 1 ... 5, 2):
                [4]
            case (38, 5, 3), (48, 5, 3), (38, 2, 5), (48, 2, 5):
                group
            case (38, 2, 6), (48, 2, 6):
                Array(group.prefix(2) + group.suffix(3))
            case (4, _, _), (38, _, _), (48, _, _), (58, _, _):
                []
            default:
                [group[0]]
            }
        }

        private static func color(from parameters: inout IndexingIterator<[Int]>) -> Color? {
            switch parameters.next() {
            case 5:
                guard let index = parameters.next().flatMap(UInt8.init(exactly:)) else {
                    return nil
                }
                return .indexed(index)
            case 2:
                let values = [parameters.next(), parameters.next(), parameters.next()]
                    .compactMap { $0.flatMap(UInt8.init(exactly:)) }
                guard values.count == 3 else {
                    return nil
                }
                return .rgb(red: values[0], green: values[1], blue: values[2])
            default:
                return nil
            }
        }
    }
}
