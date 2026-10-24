# TerminalKit

Native macOS terminal view in SwiftUI and AppKit.

## Core technologies

<table>
  <tr><td><b>Platform</b></td><td>macOS 27</td></tr>
  <tr><td><b>Dependencies</b></td><td>None</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6, with a small C target</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI and AppKit</td></tr>
  <tr><td><b>Concurrency</b></td><td>Swift 6 strict concurrency and <a href="https://developer.apple.com/documentation/observation">Observation</a></td></tr>
</table>

## Quality gates

- **Tests:** 635 [Swift Testing](https://github.com/swiftlang/swift-testing) tests cover every layer, and many run real programs in pseudo terminals.
- **CI:** GitHub Actions lints and runs the full suite on every pull request that is ready for review.
- **Accessibility:** VoiceOver reads the terminal as a text area and gets a notification when the output changes.

## Usage example

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/mazzsva/TerminalKit", branch: "main")
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

## Engineering decisions

**Built for Claude Code.** Each protocol traces to the official Claude Code docs: the kitty keyboard protocol for Shift-Return, synchronized output, mouse hover, color queries for the automatic theme, and hyperlinks.

**Written from scratch.** The whole library, from the escape sequence parser and the pseudo terminal to the view, is fewer than 5,000 lines of Swift and C on POSIX and AppKit APIs.

**A value-type emulator.** The full terminal state is one Swift struct. Tests feed it bytes and compare values. During synchronized output, the view draws a frozen copy, so the screen never shows a frame that is half drawn.

**Safe links.** A Command-click opens web, mail, FTP, and file links, both hyperlinks and plain URLs. A file link to an app or an executable, even through a symbolic link, shows it in the Finder and never launches it.

**The right size from the first frame.** The process starts only after the first layout of the view, so a full-screen program never draws its first frame at the wrong width and then redraws.

**Native AppKit behavior.** Input methods, dictation, the find bar, Services, and VoiceOver use the same AppKit APIs as a text view, and Find uses the standard menu actions, so the host app keeps its shortcuts.

**Never touches the shell.** There are no shell integration scripts and no changes to startup files. The host gets the user's own login shell, with the same `PATH` as in Terminal.
