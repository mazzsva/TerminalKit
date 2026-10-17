import CTerminalCore

extension Unicode.Scalar {
    var width: Int {
        guard !isASCII else {
            return 1
        }
        let width = Int(character_width(value))
        return width < 0 ? 1 : width
    }
}
