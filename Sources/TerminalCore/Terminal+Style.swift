extension Terminal {
    package struct Style: Equatable, Sendable {
        package var isBold = false
        package var isFaint = false
        package var isItalic = false
        package var isUnderlined = false
        package var isInverse = false
        package var isHidden = false
        package var isStrikethrough = false

        mutating func apply(_ parameters: [Int]) {
            var parameters = (parameters.isEmpty ? [0] : parameters).makeIterator()
            while let parameter = parameters.next() {
                switch parameter {
                case 0:
                    self = Style()
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
                default:
                    break
                }
            }
        }
    }
}
