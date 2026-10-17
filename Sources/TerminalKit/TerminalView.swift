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

    func makeNSView(context: Context) -> TerminalScrollView {
        TerminalScrollView(session: session)
    }

    func updateNSView(_ view: TerminalScrollView, context: Context) {
        if view.terminalView.session !== session {
            view.terminalView.session = session
        }
        let font = context.environment.terminalFont ?? TerminalContentView.defaultFont
        if view.terminalView.font != font {
            view.terminalView.font = font
        }
        let scrollIndicatorVisibility = context.environment.verticalScrollIndicatorVisibility
        view.hasVerticalScroller = scrollIndicatorVisibility != .hidden && scrollIndicatorVisibility != .never
    }
}
