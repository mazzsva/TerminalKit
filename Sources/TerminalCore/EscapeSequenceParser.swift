struct EscapeSequenceParser: Sendable {
    enum Action: Equatable, Sendable {
        case print(Unicode.Scalar)
        case execute(Unicode.Scalar)
        case escape(intermediates: String, final: Unicode.Scalar)
        case controlSequence(ControlSequence)
        case operatingSystemCommand(String)
    }

    struct ControlSequence: Equatable, Sendable {
        var privateMarker: Unicode.Scalar?
        var parameters: [Int]
        var intermediates: String
        var final: Unicode.Scalar

        func parameter(at index: Int, default defaultValue: Int) -> Int {
            guard parameters.indices.contains(index), parameters[index] != 0 else {
                return defaultValue
            }
            return parameters[index]
        }
    }

    private enum State {
        case ground
        case escape
        case escapeIntermediate
        case controlSequence
        case controlSequenceIntermediate
        case ignoredControlSequence
        case operatingSystemCommand
        case ignoredString
    }

    private static let maximumIntermediates = 2
    private static let maximumParameters = 32
    private static let maximumParameterValue = Int(Int32.max)
    private static let maximumStringLength = 4_096

    private var state = State.ground
    private var intermediates = ""
    private var privateMarker: Unicode.Scalar?
    private var parameters: [Int] = []
    private var isOverflowing = false
    private var hasLargeParameter = false
    private var string: [Unicode.Scalar] = []

    mutating func advance(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "\u{1B}":
            let action = state == .operatingSystemCommand ? finishString() : nil
            enterEscape()
            return action
        case "\u{7}" where state == .operatingSystemCommand:
            return finishString()
        case "\u{18}" where isInString, "\u{1A}" where isInString:
            state = .ground
            return .execute(scalar)
        case "\u{18}", "\u{1A}":
            return nil
        case "\u{0}" ... "\u{1F}" where isInString:
            return nil
        case "\t":
            state = .ground
            return .execute(scalar)
        case "\u{0}" ... "\u{1F}":
            return .execute(scalar)
        case "\u{7F}":
            if !isInString {
                state = .ground
            }
            return nil
        default:
            break
        }

        switch state {
        case .ground:
            return .print(scalar)
        case .escape:
            return escape(scalar)
        case .escapeIntermediate:
            return escapeIntermediate(scalar)
        case .controlSequence:
            return controlSequence(scalar)
        case .controlSequenceIntermediate:
            return controlSequenceIntermediate(scalar)
        case .ignoredControlSequence:
            return ignoredControlSequence(scalar)
        case .operatingSystemCommand:
            if string.count <= Self.maximumStringLength {
                string.append(scalar)
            }
            return nil
        case .ignoredString:
            return nil
        }
    }

    private var isInString: Bool {
        state == .operatingSystemCommand || state == .ignoredString
    }

    private mutating func escape(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "#", "(", ")", "*", "+", "-", ".", "/":
            collect(scalar)
            state = .escapeIntermediate
        case "[":
            state = .controlSequence
        case "]":
            state = .operatingSystemCommand
        case "P", "X", "^", "_":
            state = .ignoredString
        case " " ... "/":
            state = .ground
        case "0" ... "~":
            state = .ground
            return .escape(intermediates: intermediates, final: scalar)
        default:
            return .print(scalar)
        }
        return nil
    }

    private mutating func escapeIntermediate(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case " " ... "/":
            state = .ground
        case "0" ... "~":
            state = .ground
            return .escape(intermediates: intermediates, final: scalar)
        default:
            return .print(scalar)
        }
        return nil
    }

    private mutating func controlSequence(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "0" ... "9":
            if !isOverflowing {
                let value = (parameters.popLast() ?? 0) * 10 + Int(scalar.value - 0x30)
                parameters.append(min(value, Self.maximumParameterValue + 1))
                hasLargeParameter = hasLargeParameter || value > Self.maximumParameterValue
            }
        case ";":
            if parameters.count < Self.maximumParameters {
                if parameters.isEmpty {
                    parameters.append(0)
                }
                parameters.append(0)
            } else {
                isOverflowing = true
            }
        case "<" ... "?" where privateMarker == "?" || privateMarker == ">":
            state = .ground
        case "?" where parameters.isEmpty, ">" where parameters.isEmpty:
            privateMarker = scalar
        case "?", ">":
            state = .ignoredControlSequence
        case "<" where parameters.isEmpty && privateMarker == nil, "=" where parameters.isEmpty && privateMarker == nil:
            privateMarker = scalar
        case " ", "!":
            collect(scalar)
            state = .controlSequenceIntermediate
        case "@" ... "~":
            return finishControlSequence(scalar)
        case "\u{80}"...:
            return .print(scalar)
        default:
            break
        }
        return nil
    }

    private mutating func controlSequenceIntermediate(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case " " ... "/":
            guard intermediates.unicodeScalars.count < Self.maximumIntermediates else {
                state = .ground
                return .print(scalar)
            }
            collect(scalar)
        case "0" ... "?":
            state = .ground
        case "@" ... "~":
            return finishControlSequence(scalar)
        default:
            return .print(scalar)
        }
        return nil
    }

    private mutating func ignoredControlSequence(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "@" ... "~":
            state = .ground
        case "\u{80}"...:
            return .print(scalar)
        default:
            break
        }
        return nil
    }

    private mutating func enterEscape() {
        state = .escape
        intermediates = ""
        privateMarker = nil
        parameters = []
        isOverflowing = false
        hasLargeParameter = false
        string = []
    }

    private mutating func finishControlSequence(_ final: Unicode.Scalar) -> Action {
        state = .ground
        return .controlSequence(
            ControlSequence(
                privateMarker: final == "u" || privateMarker == "?" || privateMarker == ">" ? privateMarker : nil,
                parameters: hasLargeParameter
                    ? parameters.map { $0 > Self.maximumParameterValue ? 0 : $0 } : parameters,
                intermediates: intermediates,
                final: final
            )
        )
    }

    private mutating func finishString() -> Action? {
        state = .ground
        guard string.count <= Self.maximumStringLength else {
            return nil
        }
        return .operatingSystemCommand(String(String.UnicodeScalarView(string)))
    }

    private mutating func collect(_ scalar: Unicode.Scalar) {
        intermediates.unicodeScalars.append(scalar)
    }
}
