import SwiftUI

@main
struct TerminalKitExampleApp: App {
    init() {
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TextEditingCommands()
        }
    }
}
