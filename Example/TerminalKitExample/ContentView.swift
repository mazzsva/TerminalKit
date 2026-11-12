import AppKit
import SwiftUI
import TerminalKit

struct ContentView: View {
    @State private var session = TerminalSession()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        TerminalView(session: session)
            .navigationTitle(session.title.isEmpty ? "Terminal" : session.title)
            .navigationSubtitle(session.currentDirectoryURL?.path(percentEncoded: false) ?? "")
            .onChange(of: session.bellCount) {
                NSApp.requestUserAttention(.informationalRequest)
            }
            .onChange(of: session.state) {
                if case .exited = session.state {
                    dismissWindow()
                }
            }
            .task {
                try? session.start()
            }
            .onDisappear {
                session.terminate()
            }
    }
}

#Preview {
    ContentView()
}
