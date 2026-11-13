# Terminal for agent tools

Status: accepted

## Goal
TerminalKit aimed at an exact replica of Terminal.app. That aim has no end, and it copied rules of Terminal.app that differ from the standard that programs expect. The new aim is a native terminal view for Mac apps in which a login shell and agent tools such as Claude Code work as well as in the best Mac terminals. The change affects each host app that shows `TerminalView`, and the README, which states the old aim.

## Decisions
- The measure of done is a fixed list of programs that run correctly, not parity with Terminal.app. It is the choice most likely to change first.
- The repository gets an example app.
- The owner does no manual test, so each proof is automatic.
- Codex is not on the program list for now.
- The code base holds only what the aim needs. Code stays only when a listed program uses it, a person uses it in the view, it keeps bad input from causing a crash or a hang, or the host app needs it. A test stays only when it proves a requirement or protects code that stays.
- The program list is the zsh login shell, vim, less, man, top, nano, git, and Claude Code (assumed)
- Terminal.app stays the model for what a person does in the view: selection, copy, paste, drag and drop, scroll, Find, VoiceOver, and the default look (assumed)
- Terminal.app is the reference for a known limit. A behavior that is the same in Terminal.app is not a limit. The README names a difference only when Terminal.app does more, or when a person who uses the view must know it.
- For the emulator, a program uses a control function when it sent it in a measured session, or when the terminfo entry of `xterm-256color` on macOS holds it.
- Of the features that #239 to #248 and #312 removed, two come back: the title stack, because vim uses it, and OSC 8 marked links, because Claude Code sends them when the environment holds `FORCE_HYPERLINK=1`. Another one comes back only when a listed program uses it with the terminal name below.
- TerminalKit keeps the terminal name `Apple_Terminal`. In a measurement, Claude Code sent the same control sequences with each honest name, and this name makes the shell report the current directory.
- The host app gets the signals that an app needs to follow a session: title, bell, notification, current directory, and process exit (assumed)
- The host app also gets the status that a program reports with the Program Status Protocol (OSC 7501), because Claude Code reports with it when it works, waits for a permission, or is done, and its bell comes late or not at all. TerminalKit answers the query of that protocol, though Terminal.app does not.
- The owner tags 2.0.0 when each requirement passes. After that, only a measured defect becomes work (assumed)

## Requirements
1. The repository has an example Mac app that shows one `TerminalView` with the user's login shell, and it builds with no warnings.
2. In a session with no window, each system program on the list completes a fixed script, and after each step the screen holds the expected text and the cursor is at the expected position.
3. In the example app, a real Claude Code session completes a fixed script: start, a prompt with an answer, a tool run with a permission request, the slash command menu, input of two lines, a paste, a scroll of the transcript, a window resize, and exit. After each step the screen holds the expected text, and no row holds text from an earlier frame.
4. Shift-Return makes a new line in the input of Claude Code, with no setup by the user.
5. TerminalKit acts on each control sequence and answers each query that a listed program sends during its script. A test lists each one that TerminalKit ignores on purpose, and the README names each of those that Terminal.app acts on.
6. While a program redraws the full screen of 200 columns by 60 rows on each key, the view never draws a frame that the program did not complete.
7. A Command-click opens a link that a program marks or prints, with the safe link rules that exist now.
8. The host app can read the title, the current directory, and the status that a program reports, and gets an event for the bell, for a notification that a program requests, and for the exit of the process.
9. In a release build, the output of a 100 MB text file takes no longer than in Terminal.app, and one resize step with 100,000 saved lines takes less than 100 ms.
10. A run of 1,000,000 byte streams, random and made from the sequence grammar, causes no crash and no hang.
11. What a person does in the view stays as it is now: each current test of selection, copy, paste, drag and drop, scroll, Find, and VoiceOver passes.
12. The README states the new aim, the program list, and each known limit, and no line says "as in Terminal" about a behavior that now differs.
13. A coverage report of the sessions of the listed programs, the tests of the view, and the bad input run shows each function in `Sources` as used, apart from the functions that a list in the repository names with a reason for each.

## Edge cases
Each one needs a test.
- A program begins a synchronized update and never ends it: the view draws again after 1 s at most.
- No account for Claude Code in the test environment, as in CI: the real session test reports that it did not run, and the recorded session tests run.
- A recorded session in the repository: it holds no user name, no home path, no account data, and no token.
- A listed program is not installed: its test reports that it did not run, and does not pass.

## Out of scope
- Parity with a quirk or a bug of Terminal.app, and new recordings of them
- Windows, tabs, split views, profiles, and a settings window
- Session tracking, shell integration scripts, and restoration of sessions
- Host apps. The repository holds only the package and the example app
- Codex, other agent tools, tmux, and ssh. A defect there becomes a fix after 2.0.0
- Images in the terminal, and ligatures

## Constraints
- Reference: `Tests/TerminalCoreTests/PseudoTerminalTests.swift`, which runs a real program in a pseudo terminal
- Restore a removed feature from the Git history, with its tests. Do not write it again
- No dependencies, macOS 27, Swift 6 strict concurrency, and no change to the user's shell startup files
- A real session runs with an empty home folder and a fixed project
- A Terminal.app recording stays only while it protects code that stays. The recordings that remain are a safety net during the removal of code, and a later decision keeps or removes them
- Each pull request is small, uses the repository template, and merges only after CI passes

## Check
- `swift format lint --recursive --strict Package.swift Sources Tests Example`: no output
- `xcodebuild test -scheme TerminalKit -destination 'platform=macOS'`: `** TEST SUCCEEDED **`
- `xcodebuild build` for the scheme of the example app: `** BUILD SUCCEEDED **` and no warning
- The real session test on this Mac: Claude Code passes, and does not report that it did not run
- `TERMINALKIT_CLAUDE_SESSION=1 Scripts/unused-functions.sh`: exit status 0, the line `The real Claude Code session ran`, and a last line that ends with `unused ones is on the list`
- In the example app, type `claude` and press Return: the start screen of Claude Code shows

## Deviations
- Constraint "A real session runs with an empty home folder": the real Claude Code tests use the real home folder and an empty project folder, because the account of Claude Code lives in the home folder.
- Requirement 3 "In the example app": the real Claude Code session runs in a window of the test process that hosts the same `TerminalView` as the example app, not in the example app itself, because a test that drives the app needs the Accessibility permission. The test sends key and scroll wheel events through the window, pastes with the paste function of `TerminalSession`, and resizes the window. The same script also runs with no window, in a pseudo terminal with the TerminalKit emulator, and that session is the one that the recorder records.
- Requirement 3 "a scroll of the transcript": the window test scrolls the view until the earlier answer shows, and then back to the bottom. The test with no window only checks that the earlier answer is in the saved lines, because that session has no view.
- Edge case "No account for Claude Code": the real session tests run only when `TERMINALKIT_CLAUDE_SESSION` is set and Claude Code is installed, and otherwise report that they did not run. With the variable set and no account, they fail, because the tests have no check for an account.
- Requirement 8 "a notification that a program requests": the host gets no separate notification event. It observes `bellCount` of `TerminalSession`, and TerminalKit ignores OSC 9 and OSC 777, because no listed program sends them in its script.
- Synchronized output (mode 2026): TerminalKit sets `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` in the environment, unless the host sets it, because Claude Code does not use mode 2026 with the name `Apple_Terminal` without it.
- Marked links (OSC 8): TerminalKit sets `FORCE_HYPERLINK=1` in the environment, unless the host sets it, because Claude Code sends no OSC 8 with the name `Apple_Terminal` without it.
- Requirement 9 "takes no longer than in Terminal.app": the test compares live and passes when the TerminalKit time is at most 1.1 times the Terminal.app time, because the 10% is for measurement noise.
- Decision "when the terminfo entry of `xterm-256color` on macOS holds it": TerminalKit ignores SGR 5 (blink), `CSI ?1034l`, the media copy sequences `CSI i`, `CSI 4i`, and `CSI 5i`, the memory lock `ESC l` and `ESC m`, and modes 3 and 4, which `is2` and `rs2` reset, though the entry holds them, because no listed program sends them in its script. Of these, Terminal.app acts only on SGR 5. `CSI ?1034l` was not measured there.
- Requirement 5 "answers each query": TerminalKit gives no answer to the queries `CSI ?$p`, `CSI >q`, and `CSI ?u`, because each listed program completes its script with no answer to them. Terminal.app gives no answer to them either.
- Decision "Terminal.app stays the model for what a person does in the view": a copy drops the spaces at the end of each row that does not continue on the next row, where Terminal.app keeps the spaces that a program printed, because a row that a full-screen program fills with spaces would paste with them.
- Decision "Terminal.app is the reference for a known limit": the README also names the notification requests OSC 9 and OSC 777, which Terminal.app ignores too, because a person who makes a host app for agent tools must know them.
- Requirement 11 "stays as it is now": after 2.0.0, a compare with Terminal.app changed five behaviors of the view, and their tests changed with them, because Terminal.app is the model for what a person does in the view. The saved lines hold the normal screen while the alternate screen shows (#357), so the rule that kept the last saved row apart from the alternate screen is gone (#363). Page Up and Page Down move by whole rows (#358). Find scrolls the row of the match to the middle of the view (#352). The space of a legacy scroller always stays (#360), so the second fit of the terminal is gone (#362).
- Requirement 10: the bad input run is in its own test target, `BadInputTests`, so that it runs in a process of its own.
- Requirement 2 "the cursor is at the expected position": for top, the test checks that the cursor is on the last row, at the end of its text, and does not check a fixed column, because that row shows live process data.
- Check "In the example app, type `claude` and press Return": it was checked one time in the example app, with key events posted to its process. The window test is the automatic proof.
