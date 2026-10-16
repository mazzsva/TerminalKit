package struct EscapeSequenceParser: Sendable {
    package enum Action: Equatable, Sendable {
        case print(Unicode.Scalar)
        case execute(Unicode.Scalar)
        case escape(intermediates: String, final: Unicode.Scalar)
    }

    private enum State {
        case ground
        case escape
        case escapeIntermediate
    }

    private static let maximumIntermediates = 2

    private var state = State.ground
    private var intermediates = ""

    package init() {}

    package mutating func parse(_ scalars: some Sequence<Unicode.Scalar>) -> [Action] {
        scalars.compactMap { advance($0) }
    }

    private mutating func advance(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "\u{18}", "\u{1A}":
            state = .ground
            return .execute(scalar)
        case "\u{1B}":
            enterEscape()
            return nil
        case "\u{0}" ... "\u{1F}":
            return .execute(scalar)
        default:
            break
        }

        switch state {
        case .ground:
            return ground(scalar)
        case .escape:
            return escape(scalar)
        case .escapeIntermediate:
            return escapeIntermediate(scalar)
        }
    }

    private func ground(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "\u{7F}" ... "\u{9F}":
            nil
        default:
            .print(scalar)
        }
    }

    private mutating func escape(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case " " ... "/":
            collect(scalar)
            state = .escapeIntermediate
        case "0" ... "~":
            state = .ground
            return .escape(intermediates: intermediates, final: scalar)
        default:
            break
        }
        return nil
    }

    private mutating func escapeIntermediate(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case " " ... "/":
            collect(scalar)
        case "0" ... "~":
            state = .ground
            return .escape(intermediates: intermediates, final: scalar)
        default:
            break
        }
        return nil
    }

    private mutating func enterEscape() {
        state = .escape
        intermediates = ""
    }

    private mutating func collect(_ scalar: Unicode.Scalar) {
        if intermediates.unicodeScalars.count < Self.maximumIntermediates {
            intermediates.unicodeScalars.append(scalar)
        }
    }
}
