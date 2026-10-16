package struct EscapeSequenceParser: Sendable {
    package enum Action: Equatable, Sendable {
        case print(Unicode.Scalar)
        case execute(Unicode.Scalar)
    }

    package init() {}

    package func parse(_ scalars: some Sequence<Unicode.Scalar>) -> [Action] {
        scalars.compactMap { scalar in
            switch scalar {
            case "\u{0}" ... "\u{1F}":
                .execute(scalar)
            case "\u{7F}" ... "\u{9F}":
                nil
            default:
                .print(scalar)
            }
        }
    }
}
