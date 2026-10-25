import CTerminalCore

extension Unicode.Scalar {
    var width: Int {
        guard !isASCII else {
            return 1
        }
        let width = Int(character_width(value))
        guard width < 0 else {
            return width
        }
        if self != "\u{AD}",
            properties.isDefaultIgnorableCodePoint
                || [.nonspacingMark, .enclosingMark, .format].contains(properties.generalCategory)
        {
            return 0
        }
        if properties.isEmojiPresentation || properties.isIdeographic || ("\u{2E80}" ... "\u{A4CF}").contains(self) {
            return 2
        }
        return 1
    }
}
