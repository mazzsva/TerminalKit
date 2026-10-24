# TerminalKit

Native macOS terminal view in SwiftUI and AppKit.

```swift
struct ContentView: View {
    @State private var session = TerminalSession(configuration: .loginShell(running: ["claude"]))

    var body: some View {
        TerminalView(session: session)
            .task { try? session.start() }
    }
}
```

Add it with Swift Package Manager: `.package(url: "https://github.com/mazzsva/TerminalKit", branch: "main")`.

## Technologies

<table>
  <tr><td><b>Platform</b></td><td>macOS 27</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6, with a small C target</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI and AppKit</td></tr>
  <tr><td><b>Concurrency</b></td><td>Swift 6 strict concurrency and <a href="https://developer.apple.com/documentation/observation">Observation</a></td></tr>
  <tr><td><b>Dependencies</b></td><td>None</td></tr>
  <tr><td><b>Testing</b></td><td><a href="https://github.com/swiftlang/swift-testing">Swift Testing</a></td></tr>
</table>

## Engineering

**Written from scratch.** The whole library, from the escape sequence parser and the pseudo terminal to the view, is fewer than 5,000 lines of Swift and C on POSIX and AppKit APIs.

**A value-type emulator.** The full terminal state is one Swift struct. Tests feed it bytes and compare values. During synchronized output, the view draws a frozen copy, so the screen never shows a frame that is half drawn.

**Built for Claude Code.** Each protocol traces to the official Claude Code documentation: the kitty keyboard protocol for Shift-Return, synchronized output, mouse hover in fullscreen mode, color queries for the automatic theme, and hyperlinks.

**The right size from the first frame.** The process starts only after the first layout of the view, so a full-screen program never draws its first frame at the wrong width and then redraws.

**Native AppKit behavior.** Input methods, dictation, the system find bar, Services, and VoiceOver use the same AppKit APIs as a text view. The view answers the standard Find menu actions, so it never takes a shortcut from the host app.

**Never touches the shell.** There are no shell integration scripts and no changes to startup files. The host gets the user's own login shell, with the same `PATH` as in Terminal.

**Safe links.** A Command-click opens the hyperlinks that a program writes and the plain URLs in its output, but only web, mail, FTP, and file links. A file link to an app or an executable, even through a symbolic link, shows the file in the Finder and never launches it.

## Quality

- **Tests:** 635 tests cover the parser, the emulator, and the view, and run real programs in pseudo terminals.
- **CI:** GitHub Actions lints and runs the full suite on every pull request that is ready for review.
- **Accessibility:** VoiceOver reads the terminal as a text area and gets a notification when the output changes.
