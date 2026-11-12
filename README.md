# TerminalKit

Native macOS terminal view for SwiftUI, built on AppKit.

TerminalKit is a terminal view for Mac apps in which a login shell and agent tools such as Claude Code work as well as in the best Mac terminals. Terminal.app stays the model only for what a person does in the view: selection, copy, paste, drag and drop, scroll, Find, VoiceOver, and the default look.

## Core technologies

<table>
  <tr><td><b>Platform</b></td><td>macOS 27</td></tr>
  <tr><td><b>Dependencies</b></td><td>None</td></tr>
  <tr><td><b>Language</b></td><td>Swift 6, with a small C target</td></tr>
  <tr><td><b>Interface</b></td><td>SwiftUI and AppKit</td></tr>
  <tr><td><b>Concurrency</b></td><td>Swift 6 strict concurrency and <a href="https://developer.apple.com/documentation/observation">Observation</a></td></tr>
</table>

## Quality gates

- **Tests:** [Swift Testing](https://github.com/swiftlang/swift-testing) tests in three targets. `TerminalCoreTests` tests the emulator and plays byte streams recorded from Terminal.app. `TerminalKitTests` runs the listed programs in pseudo terminals and tests the view. `BadInputTests` sends 1,000,000 random byte streams in a process of its own.
- **Programs:** The zsh login shell, vim, less, man, top, nano, git, and Claude Code each complete a fixed script in `ProgramSessionTests`. After each step, the test checks the screen.
- **Claude Code:** The real session runs only on request, with Claude Code installed and signed in. CI plays a recorded session that holds no private data, and the value `record` records it again. Without `TERMINALKIT_CLAUDE_SESSION` or without Claude Code, the test reports that it did not run:
  `TEST_RUNNER_TERMINALKIT_CLAUDE_SESSION=1 xcodebuild test -scheme TerminalKit -destination 'platform=macOS' -only-testing:'TerminalKitTests/ProgramSessionTests/claudeCode()'`
- **Speed:** `TERMINALKIT_SPEED=1 swift test -c release -Xswiftc -enable-testing --filter SpeedTests` outputs 100 MB of text and resizes the view with 100,000 saved lines. It opens a Terminal.app window to compare the output time live.
- **Coverage:** `TERMINALKIT_CLAUDE_SESSION=1 Scripts/unused-functions.sh` reports each function in `Sources` that the program sessions, the view tests, and the bad input run do not use. `Scripts/unused-functions.txt` lists the expected ones, with a reason for each.
- **CI:** GitHub Actions lints, builds the example app, and runs the full suite on every pull request that is ready for review.
- **Accessibility:** VoiceOver reads the terminal as a text area and gets a notification when the output changes.

## Usage example

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/mazzsva/TerminalKit", from: "2.0.0")
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

In bracketed paste mode, `paste(_:)` sends nothing when the text contains the end marker `ESC [201~`, also when a combining mark follows it.

Set the font, the colors, and Option as Meta with `terminalFont(_:)`, `terminalPalette(_:)`, and `terminalOptionAsMetaKey(_:)`. To show the find bar with Command-F, add `TextEditingCommands()` to the `commands` of the scene. In an AppKit window, put `TerminalView` in an `NSHostingView`.

To follow a session, observe `title`, `currentDirectoryURL`, `bellCount`, and `state` of `TerminalSession`.

Do not run Claude Code's `/terminal-setup` in the host. Claude Code treats the session as Terminal.app, so the command changes the user's Terminal.app profile, not the host. Shift-Return makes a new line with no setup.

As in Terminal, hold Fn to select text while a program such as Claude Code uses the mouse.

macOS gives microphone access to the host app, not to the program in the terminal. To use Claude Code voice dictation, add `NSMicrophoneUsageDescription` to the host's Info.plist, and with the hardened runtime, the `com.apple.security.device.audio-input` entitlement.

The example app in `Example/TerminalKitExample.xcodeproj` shows one `TerminalView` with the user's login shell. Build it with the `TerminalKitExample` scheme.

## Engineering decisions

**A fixed list of programs.** The measure of done is the list of programs above, not parity with Terminal.app. The emulator acts on a control function when a listed program sends it, or when the macOS terminfo entry of `xterm-256color` holds it, and the known limits name each exception. Shift-Return makes a new line in Claude Code with no setup, through xterm's modifyOtherKeys.

**Written from scratch.** The whole library, from the escape sequence parser and the pseudo terminal to the view, is fewer than 7,000 lines of Swift and C on POSIX and AppKit APIs.

**A value-type emulator.** The full terminal state is one Swift struct. Tests feed it bytes and compare values.

**Safe links.** A Command-click opens printed web, mail, FTP, and file links. A file link to an app, an executable, or a Finder alias, even through a symbolic link, shows it in the Finder and never launches it.

**The right size from the first frame.** When the host calls `start()` after it makes the view, as in the example, the process waits until the view has its size, so a full-screen program never draws its first frame at the wrong width and then redraws.

**Native AppKit behavior.** Input methods, dictation, the find bar, Services, and VoiceOver use the same AppKit APIs as a text view, and Find uses the standard menu actions, so the host app keeps its shortcuts.

**Never touches the shell.** There are no shell integration scripts and no changes to startup files. The user's own shell starts through `/usr/bin/login`. Programs see `TERM_PROGRAM=Apple_Terminal`, and the library leaves out `TERM_SESSION_ID`, so the shell history stays in its usual file. The library also sets `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1`, so Claude Code uses synchronized output.

## Known limits

- TerminalKit keeps at most 100,000 saved lines.
- TerminalKit draws with the 12 pt system monospaced font in a 7 by 15 point cell, not with the font of Terminal.app, so some glyph shapes differ a little.
- The listed programs send these control sequences, and TerminalKit ignores them on purpose. A query among them gets no answer.
  - `ESC \`: the end of a DCS, APC, PM, or SOS string. TerminalKit ignores the string.
  - `CSI 0%m`: an SGR sequence with the intermediate `%`.
  - `CSI 29m`: TerminalKit has no crossed-out text.
  - `CSI ?$p`: the query of a mode.
  - `CSI ?12h` and `CSI ?12l`: the cursor never blinks.
  - `CSI ?1034h`: the eighth bit for Meta. The host sets Option as Meta with `terminalOptionAsMetaKey(_:)`.
  - `C0 0F`: SI. TerminalKit has no G1 character set.
  - `CSI >q`: the query of the terminal version.
  - `CSI ?u`: the query of the kitty keyboard flags.
  - `CSI ?1016l`: mode 1016, mouse positions in pixels.
  - `CSI ?2031h` and `CSI ?2031l`: mode 2031. Programs get no report when the appearance changes between light and dark.
  - `OSC 7501`.
- TerminalKit also ignores these, which no listed program sends:
  - SGR 5 (blink), and colors with colon parameters, such as `CSI 38:2::255:0:0m`.
  - OSC 8 marked links. A Command-click opens printed links only.
  - OSC 9 and OSC 777, the notification requests of programs. A host gets no notification event from a program. The bell is the only signal, through `bellCount`.
  - OSC 4 queries, OSC 5, OSC 10 and 11 that set a color, OSC 13 to 19, and OSC 104, 105, 110, 111, and 117.
  - The window reports `CSI 11t`, `CSI 13t`, `CSI 14t`, and `CSI 18t`, and DECREQTPARM.
  - SO, LS2, LS3, the G1 to G3 character sets, and the national character sets.
  - Mouse modes 1005 and 1015, DECOM, DECALN, mode 47, and LNM.
  - `CSI ?1034l`: the end of the eighth bit for Meta.
  - `CSI i`, `CSI 4i`, and `CSI 5i`: media copy. TerminalKit has no printer.
  - `ESC l` and `ESC m`: memory lock and unlock.
  - Modes 3 (132 columns) and 4 (smooth scroll). TerminalKit never has them, and the terminfo reset strings only reset them.
