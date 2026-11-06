extension Terminal {
    private static let characterSets: [Unicode.Scalar: [Unicode.Scalar: Unicode.Scalar]] = {
        var sets: [Unicode.Scalar: [Unicode.Scalar: Unicode.Scalar]] = [:]
        for set in characterSetTable {
            let map = Dictionary(uniqueKeysWithValues: zip(set.from.unicodeScalars, set.to.unicodeScalars))
            for final in set.finals.unicodeScalars {
                sets[final] = map
            }
        }
        return sets
    }()

    private static let characterSetTable: [(finals: String, from: String, to: String)] = [
        (finals: "0", from: "`abcdefghijklmnopqrstuvwxyz{|}~", to: "◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·"),
        (finals: "2", from: "`abcdefghijklmnopqrstuvwxyz{|}~", to: "◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£"),
        (finals: "4", from: "#@[\\]{|}~", to: "£¾ÿ½¦¨ƒ¼´"),
        (finals: "5C", from: "[\\]^`{|}~", to: "ÄöÅÜéäöåü"),
        (finals: "6E`", from: "[\\]{|}", to: "ÆØÅæøå"),
        (finals: "7H", from: "@[\\]^`{|}~", to: "ÉÄöÅÜéäöåü"),
        (finals: "=", from: "#@[\\]^_`{|}~", to: "ùàéçêîèôäöüû"),
        (finals: "A", from: "#", to: "£"),
        (finals: "K", from: "@[\\]{|}~", to: "§ÄöÜäö¨ß"),
        (finals: "Q", from: "@[\\]^`{|}~", to: "àâçêîôéùèû"),
        (finals: "R", from: "#@[\\]{|}~", to: "£à°ç§éùè¨"),
        (finals: "Y", from: "#@[\\]`{|}~", to: "£§°çéùàòèì"),
        (finals: "Z", from: "#@[\\]{|}~", to: "£§¡Ñ¿`°ñç"),
    ]

    static func translated(_ scalar: Unicode.Scalar, byCharacterSet final: Unicode.Scalar) -> Unicode.Scalar {
        characterSets[final]?[scalar] ?? scalar
    }
}
