import SwiftUI

public struct TerminalView: View {
    public let session: TerminalSession

    public init(session: TerminalSession) {
        self.session = session
    }

    public var body: some View {
        Representable(session: session)
    }
}

private struct Representable: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalContentView {
        TerminalContentView(session: session)
    }

    func updateNSView(_ view: TerminalContentView, context: Context) {
        if view.session !== session {
            view.session = session
        }
    }
}
