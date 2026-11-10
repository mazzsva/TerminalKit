extension Terminal {
    private static let lineDrawingCharacters = Dictionary(
        uniqueKeysWithValues: zip(
            "`abcdefghijklmnopqrstuvwxyz{|}~".unicodeScalars,
            "◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·".unicodeScalars
        )
    )

    static func lineDrawingCharacter(for scalar: Unicode.Scalar) -> Unicode.Scalar {
        lineDrawingCharacters[scalar] ?? scalar
    }
}
