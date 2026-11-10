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
- For the emulator, a program uses a control function when it sent it in a measured session, or when the terminfo entry of `xterm-256color` on macOS holds it.
- Of the features that #239 to #248 and #312 removed, only the title stack comes back, because vim uses it. Another one comes back only when a listed program uses it with the terminal name below.
- TerminalKit keeps the terminal name `Apple_Terminal`. In a measurement, Claude Code sent the same control sequences with each honest name, and this name makes the shell report the current directory.
- The host app gets the signals that an app needs to follow a session: title, bell, notification, current directory, and process exit (assumed)
- The owner tags 2.0.0 when each requirement passes. After that, only a measured defect becomes work (assumed)

## Requirements
1. The repository has an example Mac app that shows one `TerminalView` with the user's login shell, and it builds with no warnings.
2. In a session with no window, each system program on the list completes a fixed script, and after each step the screen holds the expected text and the cursor is at the expected position.
3. In the example app, a real Claude Code session completes a fixed script: start, a prompt with an answer, a tool run with a permission request, the slash command menu, input of two lines, a paste, a scroll of the transcript, a window resize, and exit. After each step the screen holds the expected text, and no row holds text from an earlier frame.
4. Shift-Return makes a new line in the input of Claude Code, with no setup by the user.
5. TerminalKit acts on each control sequence and answers each query that a listed program sends during its script. A test lists them, and the README names each one that TerminalKit ignores on purpose.
6. While a program redraws the full screen of 200 columns by 60 rows on each key, the view never draws a frame that the program did not complete.
7. A Command-click opens a link that a program marks or prints, with the safe link rules that exist now.
8. The host app can read the title and the current directory, and gets an event for the bell, for a notification that a program requests, and for the exit of the process.
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
- `swift format lint --recursive --strict Package.swift Sources Tests`: no output
- `xcodebuild test -scheme TerminalKit -destination 'platform=macOS'`: `** TEST SUCCEEDED **`
- `xcodebuild build` for the scheme of the example app: `** BUILD SUCCEEDED **` and no warning
- The real session test on this Mac: Claude Code passes, and does not report that it did not run
- The coverage report: no function is unused, apart from the functions on the list
- In the example app, type `claude` and press Return: the start screen of Claude Code shows

## Deviations
