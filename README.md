# TerminalKit

Native macOS terminal view for SwiftUI, built on AppKit.

TerminalKit is a terminal view for Mac apps. In it, the zsh login shell, vim, less, man, top, nano, git, and Claude Code work at least as well as in Terminal.app, and the host app also gets the status that a program reports. Terminal.app is also the model for what a person does in the view: selection, copy, paste, drag and drop, scroll, Find, VoiceOver, and the default look.

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
- **Claude Code:** The real session runs only on request, with Claude Code installed and signed in. It runs one time in a pseudo terminal, and one time in a window that hosts the view, where the test sends key and scroll wheel events to the window and resizes it. CI plays a recorded session that holds no private data, and the value `record` records it again. Without `TERMINALKIT_CLAUDE_SESSION` or without Claude Code, the two tests report that they did not run:
  `TEST_RUNNER_TERMINALKIT_CLAUDE_SESSION=1 xcodebuild test -scheme TerminalKit -destination 'platform=macOS' -only-testing:TerminalKitTests/ProgramSessionTests`
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

Call `terminate()` when the window closes, as the example app does in `onDisappear`. macOS can keep a closed window that it restored, and the `@State` session of that window keeps its shell alive until the app quits. `onDisappear` also runs when a container such as a `TabView` hides the view, and it does not run when an AppKit window closes. In such a host, call `terminate()` when the host closes the window or the tab of the session.

Send input with `send(_:)` or `paste(_:)` only after `start()`. Input sent before `start()` is dropped.

In bracketed paste mode, `paste(_:)` sends nothing when the text contains the end marker `ESC [201~`, also when a combining mark follows it.

Set the font, the colors, and Option as Meta with `terminalFont(_:)`, `terminalPalette(_:)`, and `terminalOptionAsMetaKey(_:)`. To show the find bar with Command-F, add `TextEditingCommands()` to the `commands` of the scene. In an AppKit window, put `TerminalView` in an `NSHostingView`.

To follow a session, observe `title`, `currentDirectoryURL`, `bellCount`, `programStatus`, and `state` of `TerminalSession`. A login shell runs under `/usr/bin/login`, so its `state` at the end is an exit with status 0, also when the shell ends with another status or by a signal. A configuration with an executable of its own gives the real status.

Do not run Claude Code's `/terminal-setup` in the host. Claude Code treats the session as Terminal.app, so the command changes the user's Terminal.app profile, not the host. Shift-Return makes a new line with no setup. Claude Code names that command when an Option shortcut does nothing. For those shortcuts, turn on `terminalOptionAsMetaKey(_:)`.

With its default setting, Claude Code rings the bell only when the Terminal.app profile of the user has the audible bell off. To read that profile, it sends an Apple event to Terminal.app in the name of the host app, so macOS can ask the user to let the host control Terminal. To get the bell for a permission request and for a finished task in each case, start it with `claude --settings '{"preferredNotifChannel":"terminal_bell"}'`. The bell comes some seconds after the request, and one minute after the end of the task.

`programStatus` gives the status that a program reports: idle, working, blocked, or done. Claude Code 2.1.295 or later reports it with no setup. When it waits for a permission, the state is blocked, the kind is `permission`, and the message names the request, such as the file to write. Then Claude Code puts no status glyph in front of the title. The status is nil when the program clears it or when the session ends. A program that is killed with `SIGKILL` cannot clear it, so its last status and its title stay until another program reports.

For voice input in a program such as Claude Code, a host app with the hardened runtime needs the audio input entitlement and a microphone usage description, as the example app has.

As in Terminal, hold Fn to select text while a program such as Claude Code uses the mouse.

A held letter key with accents, such as E, shows the accent menu of macOS and does not repeat, as in a text view. For a key that repeats as in Terminal, register `ApplePressAndHoldEnabled` as `false` in the `UserDefaults` of the host app, as the example app does.

macOS gives microphone access to the host app, not to the program in the terminal. To use Claude Code voice dictation, add `NSMicrophoneUsageDescription` to the host's Info.plist, and with the hardened runtime, the `com.apple.security.device.audio-input` entitlement.

The example app in `Example/TerminalKitExample.xcodeproj` shows one `TerminalView` with the user's login shell. Build it with the `TerminalKitExample` scheme.

## Engineering decisions

**A fixed list of programs.** The measure of done is the list of programs above, not parity with Terminal.app. The emulator acts on a control function when a listed program sends it, or when the macOS terminfo entry of `xterm-256color` holds it, and the known limits name each exception that Terminal.app does not share, or that a host app must know. Shift-Return makes a new line in Claude Code with no setup, through xterm's modifyOtherKeys.

**Written from scratch.** The whole library, from the escape sequence parser and the pseudo terminal to the view, is fewer than 7,000 lines of Swift and C on POSIX and AppKit APIs.

**A value-type emulator.** The full terminal state is one Swift struct. Tests feed it bytes and compare values.

**Safe links.** A Command-click opens printed web, mail, FTP, and file links. A file link to an app, an executable, or a Finder alias, even through a symbolic link, shows it in the Finder and never launches it.

**The right size from the first frame.** When the host calls `start()` after it makes the view, as in the example, the process waits until the view has its size, so a full-screen program never draws its first frame at the wrong width and then redraws.

**Native AppKit behavior.** Input methods, dictation, the find bar, Services, and VoiceOver use the same AppKit APIs as a text view, and Find uses the standard menu actions, so the host app keeps its shortcuts.

**Never touches the shell.** There are no shell integration scripts and no changes to startup files. The user's own shell starts through `/usr/bin/login`. Programs see `TERM_PROGRAM=Apple_Terminal`, and the library leaves out `TERM_SESSION_ID`, so the shell history stays in its usual file. The library also sets `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1`, so Claude Code uses synchronized output.

## Known limits

- TerminalKit keeps at most 100,000 saved lines.
- TerminalKit draws with the 12 pt system monospaced font in a 7 by 15 point cell, not with the font of Terminal.app, so some glyph shapes differ a little.
- A person cannot drag the selected text out of the view to another app, as Terminal.app permits.
- Terminal.app acts on these, and TerminalKit ignores them, because no listed program needs them:
  - SGR 5 (blink). The text does not blink.
  - The G1 to G3 character sets with SO, SI (`C0 0F`), LS2, and LS3, and the national character sets. Line drawing works in G0, with `ESC ( 0`.
  - The color queries OSC 4, OSC 5, and OSC 13 to 19, OSC 10 and OSC 11 that set a color, and OSC 104, 110, and 111 that reset a color.
  - The window reports `CSI 11t`, `CSI 13t`, `CSI 14t`, and `CSI 18t`, and DECREQTPARM (`CSI x`).
  - DECOM, DECALN, mode 47, and LNM.
- Terminal.app does not have these either, but a host app for agent tools must know them:
  - OSC 8 marked links. A Command-click opens printed links only.
  - OSC 9 and OSC 777, the notification requests of programs. A host gets no notification event from a program. The signals are the bell, through `bellCount`, and the status that a program reports, through `programStatus`.
