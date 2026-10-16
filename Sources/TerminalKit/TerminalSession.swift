import Observation

@MainActor
@Observable
public final class TerminalSession {
    public let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }
}
