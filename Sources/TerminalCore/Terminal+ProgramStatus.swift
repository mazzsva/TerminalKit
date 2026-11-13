import Foundation

extension Terminal {
    package struct ProgramStatus: Hashable, Sendable {
        package enum State: String, Hashable, Sendable {
            case idle
            case working
            case done
            case blocked
        }

        package var state: State
        package var application: String?
        package var kind: String?
        package var message: String?
    }

    mutating func reportProgramStatus(_ text: Substring) {
        guard text != "?" else {
            replies += "\u{1B}]7501;?\u{7}".utf8
            return
        }
        var fields: [Substring: Substring] = [:]
        for field in text.split(separator: ":") {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            fields[pair[0]] = pair.count == 2 ? pair[1] : ""
        }
        guard fields["state"] != "clear" else {
            programStatus = nil
            return
        }
        guard let state = fields["state"].flatMap({ ProgramStatus.State(rawValue: String($0)) }) else {
            return
        }
        programStatus = ProgramStatus(
            state: state,
            application: fields["app"].map(String.init),
            kind: fields["kind"].map(String.init),
            message: fields["msg"].flatMap(Self.decodedMessage)
        )
    }

    private static func decodedMessage(_ text: Substring) -> String? {
        guard let data = Data(base64Encoded: String(text)), let message = String(validating: data, as: UTF8.self)
        else {
            return nil
        }
        return String(String.UnicodeScalarView(message.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
    }
}
