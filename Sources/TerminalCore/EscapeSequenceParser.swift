package struct EscapeSequenceParser: Sendable {
    package enum Action: Equatable, Sendable {
        case print(Unicode.Scalar)
        case execute(Unicode.Scalar)
        case escape(intermediates: String, final: Unicode.Scalar)
        case controlSequence(ControlSequence)
        case operatingSystemCommand(String)
    }

    package struct ControlSequence: Equatable, Sendable {
        package var privateMarker: Unicode.Scalar?
        package var parameters: [Int]
        package var intermediates: String
        package var final: Unicode.Scalar

        package func parameter(at index: Int, default defaultValue: Int) -> Int {
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
        case ignoredControlSequence
        case operatingSystemCommand
        case ignoredString
    }

    private static let maximumIntermediates = 2
    private static let maximumParameters = 32
    private static let maximumParameterValue = 65_535
    private static let maximumStringLength = 4_096

    private var state = State.ground
    private var intermediates = ""
    private var privateMarker: Unicode.Scalar?
    private var parameters: [Int] = []
    private var string: [Unicode.Scalar] = []

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
            let action = state == .operatingSystemCommand ? finishString() : nil
            enterEscape()
            return action
        case "\u{7}" where state == .operatingSystemCommand:
            return finishString()
        case "\u{0}" ... "\u{1F}":
            return state == .operatingSystemCommand || state == .ignoredString ? nil : .execute(scalar)
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
        case .controlSequence:
            return controlSequence(scalar)
        case .ignoredControlSequence:
            return ignoredControlSequence(scalar)
        case .operatingSystemCommand:
            if string.count < Self.maximumStringLength {
                string.append(scalar)
            }
            return nil
        case .ignoredString:
            return nil
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
        case "[":
            state = .controlSequence
        case "]":
            state = .operatingSystemCommand
        case "P", "X", "^", "_":
            state = .ignoredString
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

    private mutating func controlSequence(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case "0" ... "9" where intermediates.isEmpty:
            let value = (parameters.popLast() ?? 0) * 10 + Int(scalar.value - 0x30)
            parameters.append(min(value, Self.maximumParameterValue))
        case ";" where intermediates.isEmpty && parameters.count < Self.maximumParameters:
            if parameters.isEmpty {
                parameters.append(0)
            }
            parameters.append(0)
        case "<" ... "?" where intermediates.isEmpty && parameters.isEmpty && privateMarker == nil:
            privateMarker = scalar
        case "0" ... "?":
            state = .ignoredControlSequence
        case " " ... "/":
            collect(scalar)
        case "@" ... "~":
            state = .ground
            return .controlSequence(
                ControlSequence(
                    privateMarker: privateMarker,
                    parameters: parameters,
                    intermediates: intermediates,
                    final: scalar
                )
            )
        default:
            break
        }
        return nil
    }

    private mutating func ignoredControlSequence(_ scalar: Unicode.Scalar) -> Action? {
        if ("@" ... "~").contains(scalar) {
            state = .ground
        }
        return nil
    }

    private mutating func enterEscape() {
        state = .escape
        intermediates = ""
        privateMarker = nil
        parameters = []
        string = []
    }

    private mutating func finishString() -> Action {
        state = .ground
        return .operatingSystemCommand(String(String.UnicodeScalarView(string)))
    }

    private mutating func collect(_ scalar: Unicode.Scalar) {
        if intermediates.unicodeScalars.count < Self.maximumIntermediates {
            intermediates.unicodeScalars.append(scalar)
        }
    }
}
