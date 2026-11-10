import SwiftUI

@main
struct TerminalKitExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TextEditingCommands()
        }
    }
}
