import SwiftUI

public struct TerminalView: View {
    let session: TerminalSession

    public init(session: TerminalSession) {
        self.session = session
    }

    public var body: some View {
        Representable(session: session)
            .id(ObjectIdentifier(session))
    }
}

private struct Representable: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalScrollView {
        TerminalScrollView(session: session)
    }

    func updateNSView(_ view: TerminalScrollView, context: Context) {
        let font = context.environment.terminalFont ?? TerminalContentView.defaultFont
        if view.terminalView.font != font {
            view.terminalView.font = font
        }
        if view.terminalView.palette != context.environment.terminalPalette {
            view.terminalView.palette = context.environment.terminalPalette
        }
        view.terminalView.usesOptionAsMetaKey = context.environment.usesOptionAsMetaKey
        let openURL = context.environment.openURL
        view.terminalView.performLinkAction = { action in
            if case .open(let url) = action {
                openURL(url)
            } else {
                TerminalContentView.performWithWorkspace(action)
            }
        }
        let scrollIndicatorVisibility = context.environment.verticalScrollIndicatorVisibility
        view.hasVerticalScroller = scrollIndicatorVisibility != .hidden && scrollIndicatorVisibility != .never
    }
}
