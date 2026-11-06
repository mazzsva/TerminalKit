# TerminalKit

Native macOS terminal view for SwiftUI, built on AppKit.

## Core technologies

<table>
  <tr><td><b>Platform</b></td><td>macOS 27</td></tr>
  <tr><td><b>Dependencies</b></td><td>None</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6, with a small C target</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI and AppKit</td></tr>
  <tr><td><b>Concurrency</b></td><td>Swift 6 strict concurrency and <a href="https://developer.apple.com/documentation/observation">Observation</a></td></tr>
</table>

## Quality gates

- **Tests:** 888 [Swift Testing](https://github.com/swiftlang/swift-testing) tests cover every layer, and many run real programs in pseudo terminals. One test plays byte streams recorded from Terminal.app and compares the screen, the replies, and the title. `Scripts/record-terminal-app.py` records them again in a test window of its own.
- **CI:** GitHub Actions lints and runs the full suite on every pull request that is ready for review.
- **Accessibility:** VoiceOver reads the terminal as a text area and gets a notification when the output changes.

## Usage example

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/mazzsva/TerminalKit", from: "1.0.0")
```

Then show a terminal that runs Claude Code:

```swift
import SwiftUI
import TerminalKit

struct ContentView: View {
    @State private var session = TerminalSession(
        configuration: .loginShell(running: ["claude"])
    )

    var body: some View {
        TerminalView(session: session)
            .task { try? session.start() }
    }
}
```

Send input with `send(_:)` or `paste(_:)` only after `start()`. Input sent before `start()` is dropped.

Set the font, the colors, and Option as Meta with `terminalFont(_:)`, `terminalPalette(_:)`, and `terminalOptionAsMetaKey(_:)`. To show the find bar with Command-F, add `TextEditingCommands()` to the `commands` of the scene. In an AppKit window, put `TerminalView` in an `NSHostingView`.

Claude Code treats the session as Terminal.app, so `/terminal-setup` changes the user's Terminal.app profile, not the host. For Option-Return as a new line, turn on `terminalOptionAsMetaKey(_:)`.

macOS gives microphone access to the host app, not to the program in the terminal. To use Claude Code voice dictation, add `NSMicrophoneUsageDescription` to the host's Info.plist, and with the hardened runtime, the `com.apple.security.device.audio-input` entitlement.

## Engineering decisions

**Built for Claude Code.** Each protocol traces to the official Claude Code docs: the kitty keyboard protocol for Shift-Return, mouse hover, and color queries for the automatic theme.

**Written from scratch.** The whole library, from the escape sequence parser and the pseudo terminal to the view, is fewer than 5,000 lines of Swift and C on POSIX and AppKit APIs.

**A value-type emulator.** The full terminal state is one Swift struct. Tests feed it bytes and compare values.

**Safe links.** A Command-click opens web, mail, FTP, and file links. A file link to an app, an executable, or a Finder alias, even through a symbolic link, shows it in the Finder and never launches it.

**The right size from the first frame.** When the host calls `start()` after it makes the view, as in the example, the process waits until the view has its size, so a full-screen program never draws its first frame at the wrong width and then redraws.

**Native AppKit behavior.** Input methods, dictation, the find bar, Services, and VoiceOver use the same AppKit APIs as a text view, and Find uses the standard menu actions, so the host app keeps its shortcuts.

**Never touches the shell.** There are no shell integration scripts and no changes to startup files. The host gets the user's own login shell, with the same `PATH` as in Terminal. Programs see `TERM_PROGRAM=Apple_Terminal`, so they act as in Terminal, and the library leaves out `TERM_SESSION_ID`, so the shell history stays in its usual file.
