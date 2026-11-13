import AppKit
import SwiftUI
import TerminalKit

struct ContentView: View {
    @State private var session = TerminalSession()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        TerminalView(session: session)
            .navigationTitle(session.title.isEmpty ? "Terminal" : session.title)
            .navigationSubtitle(subtitle)
            .onChange(of: session.bellCount) {
                NSApp.requestUserAttention(.informationalRequest)
            }
            .onChange(of: session.programStatus?.state) { _, state in
                if state == .blocked || state == .done {
                    NSApp.requestUserAttention(.informationalRequest)
                }
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

    private var subtitle: Text {
        switch session.programStatus?.state {
        case .idle:
            Text("Idle")
        case .working:
            Text("Working")
        case .blocked:
            Text("Blocked")
        case .done:
            Text("Done")
        case nil:
            Text(verbatim: session.currentDirectoryURL?.path(percentEncoded: false) ?? "")
        }
    }
}

#Preview {
    ContentView()
}
