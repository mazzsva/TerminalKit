extension Unicode.Scalar {
    private static let lineDrawingCharacters: [Unicode.Scalar] = [
        "\u{A0}", "◆", "▒", "␉", "␌", "␍", "␊", "°", "±", "␤", "␋", "┘", "┐", "┌", "└", "┼",
        "⎺", "⎻", "─", "⎼", "⎽", "├", "┤", "┴", "┬", "│", "≤", "≥", "π", "≠", "£", "·",
    ]

    var lineDrawingCharacter: Unicode.Scalar {
        ("_" ... "~").contains(self) ? Self.lineDrawingCharacters[Int(value - 0x5F)] : self
    }
}
