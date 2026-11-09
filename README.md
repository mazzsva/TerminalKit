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

- **Tests:** 942 [Swift Testing](https://github.com/swiftlang/swift-testing) tests cover every layer, and many run real programs in pseudo terminals. One test plays byte streams recorded from Terminal.app and compares the screen, the replies, and the title. `Scripts/record-terminal-app.py` records them again in a test window of its own.
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

As in Terminal, in bracketed paste mode `paste(_:)` sends nothing when the text contains the end marker `ESC [201~`.

Set the font, the colors, and Option as Meta with `terminalFont(_:)`, `terminalPalette(_:)`, and `terminalOptionAsMetaKey(_:)`. To show the find bar with Command-F, add `TextEditingCommands()` to the `commands` of the scene. In an AppKit window, put `TerminalView` in an `NSHostingView`.

Do not run Claude Code's `/terminal-setup` in the host. Claude Code treats the session as Terminal.app, so the command changes the user's Terminal.app profile, not the host. For Option-Return as a new line, turn on `terminalOptionAsMetaKey(_:)`.

As in Terminal, hold Fn to select text while a program such as Claude Code uses the mouse.

macOS gives microphone access to the host app, not to the program in the terminal. To use Claude Code voice dictation, add `NSMicrophoneUsageDescription` to the host's Info.plist, and with the hardened runtime, the `com.apple.security.device.audio-input` entitlement.

## Engineering decisions

**Terminal.app behavior.** The screen output, the replies, the colors, the font size, resize, and the login shell follow Terminal.app 2.15, as measured in Terminal.app. Keys, the mouse, and paste were compared with the same events posted to Terminal.app. TerminalKit also has two protocols that Terminal.app does not have, because the Claude Code docs use them: the kitty keyboard protocol (flag 1) and xterm's modifyOtherKeys.

**Written from scratch.** The whole library, from the escape sequence parser and the pseudo terminal to the view, is fewer than 7,000 lines of Swift and C on POSIX and AppKit APIs.

**A value-type emulator.** The full terminal state is one Swift struct. Tests feed it bytes and compare values.

**Safe links.** A Command-click opens web, mail, FTP, and file links. A file link to an app, an executable, or a Finder alias, even through a symbolic link, shows it in the Finder and never launches it.

**The right size from the first frame.** When the host calls `start()` after it makes the view, as in the example, the process waits until the view has its size, so a full-screen program never draws its first frame at the wrong width and then redraws.

**Native AppKit behavior.** Input methods, dictation, the find bar, Services, and VoiceOver use the same AppKit APIs as a text view, and Find uses the standard menu actions, so the host app keeps its shortcuts.

**Never touches the shell.** There are no shell integration scripts and no changes to startup files. As in Terminal, the user's own shell starts through `/usr/bin/login -pf`, and the view shows `[Process completed]` when the process ends. Programs see `TERM_PROGRAM=Apple_Terminal`, so they act as in Terminal, and the library leaves out `TERM_SESSION_ID`, so the shell history stays in its usual file.

## Known differences from Terminal.app

- Terminal.app draws with its private SF Mono Terminal font. TerminalKit uses the 12 pt system monospaced font in the same 7 by 15 point cell, so some glyph shapes differ a little.
- Terminal.app leaves gaps and overlaps in some right-to-left text. TerminalKit does not copy them.
- With about 1,000,000 saved lines of wrapped text that mixes wide characters and tabs, one resize step takes about 0.7 s in a release build. Terminal.app takes about 60 ms.
