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
        var subparameters: [Int: Int]

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
        case operatingSystemCommandNumber
        case operatingSystemCommand
        case operatingSystemCommandEscape
        case ignoredString
    }

    private static let maximumIntermediates = 2
    private static let maximumParameters = 32
    private static let maximumParameterValue = Int(Int32.max)
    private static let maximumStringLength = 1_000_000

    private var state = State.ground
    private var intermediates = ""
    private var privateMarker: Unicode.Scalar?
    private var parameters: [Int] = []
    private var isOverflowing = false
    private var hasLargeParameter = false
    private var subparameters: [Int: Int] = [:]
    private var colons = 0
    private var string: [Unicode.Scalar] = []

    mutating func advance(_ scalar: Unicode.Scalar) -> Action? {
        if state == .operatingSystemCommandEscape {
            if scalar == "\\" {
                return finishString()
            }
            enterEscape()
        }
        switch scalar {
        case "\u{18}", "\u{1A}":
            state = .ground
            return nil
        case "\u{1B}" where isInOperatingSystemCommand:
            state = .operatingSystemCommandEscape
            return nil
        case "\u{1B}":
            enterEscape()
            return nil
        case "\u{7}" where isInOperatingSystemCommand:
            return finishString()
        case "\u{0}" ... "\u{1F}" where isInOperatingSystemCommand || state == .ignoredString, "\u{7F}":
            return nil
        case "\u{0}" ... "\u{1F}":
            return .execute(scalar)
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
        case .operatingSystemCommandNumber:
            return operatingSystemCommandNumber(scalar)
        case .operatingSystemCommand:
            collectString(scalar)
            return nil
        case .operatingSystemCommandEscape, .ignoredString:
            return nil
        }
    }

    private var isInOperatingSystemCommand: Bool {
        state == .operatingSystemCommandNumber || state == .operatingSystemCommand
    }

    private mutating func escape(_ scalar: Unicode.Scalar) -> Action? {
        switch scalar {
        case " " ... "/":
            collect(scalar)
            state = .escapeIntermediate
        case "[":
            state = .controlSequence
        case "]":
            state = .operatingSystemCommandNumber
        case "P", "X", "^", "_":
            state = .ignoredString
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
            collect(scalar)
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
        case "0" ... "9" where !isOverflowing:
            let digit = Int(scalar.value - 0x30)
            if colons == 0 {
                let value = (parameters.popLast() ?? 0) * 10 + digit
                parameters.append(min(value, Self.maximumParameterValue + 1))
                hasLargeParameter = hasLargeParameter || value > Self.maximumParameterValue
            } else if colons == 1, let value = subparameters[parameters.count - 1] {
                subparameters[parameters.count - 1] = min(value * 10 + digit, Self.maximumParameterValue)
            }
        case ":":
            if parameters.isEmpty {
                parameters.append(0)
            }
            colons += 1
            if colons == 1 {
                subparameters[isOverflowing ? parameters.count : parameters.count - 1] = 0
            }
        case ";":
            colons = 0
            if parameters.count < Self.maximumParameters {
                if parameters.isEmpty {
                    parameters.append(0)
                }
                parameters.append(0)
            } else {
                isOverflowing = true
            }
        case "<" ... "?" where parameters.isEmpty && privateMarker == nil:
            privateMarker = scalar
        case "<" ... "?":
            state = .ignoredControlSequence
        case " " ... "/":
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
            collect(scalar)
        case "0" ... "?":
            state = .ignoredControlSequence
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

    private mutating func operatingSystemCommandNumber(_ scalar: Unicode.Scalar) -> Action? {
        if scalar.value >= 0x80 {
            return .print(scalar)
        }
        if !("0" ... "9").contains(scalar) {
            state = .operatingSystemCommand
        }
        collectString(scalar)
        return nil
    }

    private mutating func enterEscape() {
        state = .escape
        intermediates = ""
        privateMarker = nil
        parameters = []
        isOverflowing = false
        hasLargeParameter = false
        subparameters = [:]
        colons = 0
        string = []
    }

    private mutating func finishControlSequence(_ final: Unicode.Scalar) -> Action {
        state = .ground
        return .controlSequence(
            ControlSequence(
                privateMarker: privateMarker,
                parameters: hasLargeParameter
                    ? parameters.map { $0 > Self.maximumParameterValue ? 0 : $0 } : parameters,
                intermediates: intermediates,
                final: final,
                subparameters: subparameters
            )
        )
    }

    private mutating func finishString() -> Action? {
        state = .ground
        defer { string = [] }
        let number = string.prefix { $0 != ";" }
        guard string.count <= Self.maximumStringLength, !number.isEmpty, number.allSatisfy({ "0" ... "9" ~= $0 }) else {
            return nil
        }
        return .operatingSystemCommand(String(String.UnicodeScalarView(string)))
    }

    private mutating func collectString(_ scalar: Unicode.Scalar) {
        if string.count <= Self.maximumStringLength {
            string.append(scalar)
        }
    }

    private mutating func collect(_ scalar: Unicode.Scalar) {
        if intermediates.unicodeScalars.count < Self.maximumIntermediates {
            intermediates.unicodeScalars.append(scalar)
        }
    }
}
