# Closing list

Status: accepted

## Goal
Both earlier specs are reached: `specs/terminal-for-agent-tools.md` at the tag 2.0.0, and `specs/tight-code-and-proofs.md` at the tag 2.1.0. The work after 2.1.0 used new methods (a second measurement, single change tests of the view and of the emulator, and an audit by three auditors on 2026-11-15), and each method found more small things, so the work had no end. This spec closes the work. It holds one fixed list of what the audit found wrong, gives the last code that never had the removal check that check, tests the pointer cases one time with the real pointer, and sets the rule for work after it. It affects `Sources`, `Tests`, the README, and the two earlier specs.

## Decisions
- The list of this spec is closed. A finding that is not on it goes to Deviations, not into the work, unless a requirement cannot pass without it. It is the choice most likely to change first.
- After the tag of this spec, only a defect or a need that the owner meets in real use becomes work. No audit, sample, or measurement starts without the word of the owner.
- The host gets no new API. A switch for the bell sound, a clear command, the real end status through the login shell, an end line after the exit, and a limit setting for the saved lines wait for a need from real use. The README names the way around where one exists.
- The joined emoji sequences, the Powerline arrows, and the removal of the wrap mark by `CSI J` at column 0 are possible extras that the Extras list of the second spec missed. Each one takes the removal test of the second spec, after a measurement in Terminal.app.
- The places of the single change run of 2026-11-15 get the removal check only: code that nothing needs goes, and each other place gets a name with the reason. No new test is necessary for a place.
- One worker session moves the real pointer, only in the window of the example app, and only while the owner is away from the Mac. It uses no Terminal.app window, no clipboard, and no other app, so it does not compare with Terminal.app.
- For a small control function, "Terminal.app acts on it" is a reason to stay. This covers REP, CNL, CPL, CHT, HPA, HVP, IND, NEL, VT and FF, `CSI 5n`, `CSI 1J`, `CSI 0g`, SGR 28, and the query `OSC 12;?` (assumed)
- `hasForegroundProcess` stays public, because its removal breaks the API of 2.0.0, and the README names it (assumed)
- The owner makes the tag when each requirement passes (assumed)

## Requirements
1. Output with many different chains of combining marks does not hold memory without limit. After 1 MB of output in which each cell holds `a` and 500 random marks from U+0300 to U+036F, the process holds less than 64 MB more than before (656 MB at 2.1.0). After 20 MB of output with 4 random marks for each cell, then `CSI 3J` and `ESC c`, the process holds less than 64 MB more than before the output (349 MB at 2.1.0).
2. The section `Extras` of this spec holds one line for each of the three possible extras: what Terminal.app does, what failed with the code removed, and whether it stays. When the joined emoji sequences go, the cursor moves as in Terminal.app: 4 columns after U+1F44D U+1F3FD, 8 after U+1F468 ZWJ U+1F469 ZWJ U+1F467, 1 after U+2764 U+FE0F, 1 after U+263A U+FE0F, and 2 after U+1F1EE U+1F1F9. Then, in the zsh line editor, the line `echo 👍🏽 ab ❤️ cd` with Left 7 times and `X` shows `Xab`, as zsh runs it.
3. After Page Up while output arrives, End, or Page Down to the last row, makes the view follow new output again.
4. On the alternate screen, after the window gets narrower, the view draws no cell to the right of the last column.
5. After a resize that makes the screen smaller than the scroll region of a program, a line feed at the last row scrolls the screen. An OSC whose number is too large for `Int32` changes nothing. `ESC c` keeps the current directory that the shell reported.
6. The README states each of these facts for a host: the process starts only when the view has space for 10 columns and 2 rows; `start()` throws only when the session has no view, and a failed start with a view shows as `.exited(.exit(127))`; a session starts one time, and a restart uses a new session in a view with `.id(session)`; `.loginShell(running:)` ends with status 0 for each end of the program, and a configuration with the shell and `-lic` gives the real status; `Configuration` has `currentDirectoryURL` and `environment`; `hasForegroundProcess` tells if a program runs in the shell; each bell plays the alert sound, and Command-K clears, and the host has no switch and no command for them; a new view takes the keyboard focus, and `.focused` moves it; `ansiColors` holds 16 colors; `session.currentDirectoryURL` holds only what a shell reports; `paste(_:)` sends the text as it is when the program did not turn bracketed paste on; the App Sandbox of the host must be off; 100,000 saved lines of 200 columns take about 300 MB; the view prints no line after the end of the process.
7. Each of these members of `Sources` that only tests read is gone, with the checks that need it, or Deviations says why it stays: `TerminalSession.terminalDidChange`, `TerminalContentView.drawCount`, `PseudoTerminal.unsentInputCount`, and the parameter `restoredRows` of `Terminal.resize`.
8. For each of the 134 places of the private lists `none-emulator.md` and `none-process.md` in `.claude/e2e-tools/mutation` that `equivalent.md` did not name on 2026-11-15, one of these is true: the code that the change touches is gone; a test fails when the change is in the code; or `equivalent.md` names the change with its reason. A reason is that no program and no person can observe the difference, that only a failed system call reaches the code, or that the code is necessary, with what needs it.
9. The pointer session gives a result for each of these cases in the window of the example app: a click, a double click, a triple click, a drag across a wrapped line, a drag past the top edge and past the bottom edge with autoscroll, a Shift-click, the pointer shape over text, the underline and the pointer shape of a link while Command is down, the wheel in the saved lines, the wheel on the alternate screen in `less`, a click and the wheel in vim with `:set mouse=a`, and a click, a double click, and the wheel in the fullscreen mode of Claude Code. Each case works as a person expects from Terminal.app, or its defect is corrected with a test.
10. The README says "not tested with the real pointer" or "not tested" for a drop from the Finder, input methods, and the accent menu of a held key, where one of its lines says that the thing works.
11. After the changes, the README, the three specs, and the lists of acted and ignored sequences in `ProgramSessionTests` say the same as the code. The first spec holds one Deviation line that names this spec and the reason of the Decision on small control functions.

## Edge cases
Each one needs a test.
- End with no Page Up before: the view follows the output, as it did.
- Page Down that does not get to the last row: the view stays where it is while output arrives.
- A cell that gets more combining marks than it can hold: the cell keeps the marks that it has, and no crash occurs.

## Out of scope
- New host API, and Codex, tmux, and ssh
- A new test for a place that gets a name
- A compare of the pointer cases with Terminal.app, a single Command-click that opens a link in another app, a drop from the Finder, input methods, and voice input
- A new design of the saved lines, of the resize, or of the start of the process, and a change of the rule for safe links
- The removal of the small control functions of the Decision
- A new sample of single changes, a new audit, and a new measurement that this spec does not name
- The tag, which the owner makes

## Constraints
- Reference: `Tests/TerminalCoreTests/ProgramStatusTests.swift`, which gives bytes to the emulator and compares values
- The removal test, the rule for code that goes, and the rule "no change to the product code only to make a test possible" are those of the second spec
- A measurement in Terminal.app uses only a window that the worker made in the Terminal.app process that runs, by its text and by cursor reports. No second Terminal.app process, no `open -a Terminal`, no key event to Terminal.app, and no clipboard
- The pointer session stops when a window of another app is in front, and its report names that first
- The private lists and `equivalent.md` stay in `.claude/e2e-tools/mutation`, outside Git. The repository gets no new tool and no new list file
- No dependencies, macOS 27, Swift 6 strict concurrency, and no change to the public API
- Each pull request is small, uses the repository template, and merges only after CI passes

## Check
- `swift format lint --recursive --strict Package.swift Sources Tests Example`: no output
- `xcodebuild test -scheme TerminalKit -destination 'platform=macOS'`: `** TEST SUCCEEDED **`
- `xcodebuild build` for the scheme of the example app: `** BUILD SUCCEEDED **` and no warning
- `TERMINALKIT_CLAUDE_SESSION=1 Scripts/unused-functions.sh`: exit status 0, the line `The real Claude Code session ran`, and a last line that ends with `unused ones is on the list`
- `TERMINALKIT_SPEED=1 swift test -c release -Xswiftc -enable-testing --filter SpeedTests`: the two tests pass
- The two outputs of requirement 1, given to the emulator in a test process: the memory of the process stays under each limit
- In the example app, a cursor report after each sequence of requirement 2: the column that the requirement or the `Extras` line states
- In the example app, `for i in {1..250}; do echo line $i; sleep 0.03; done`, then Page Up, then End: the last line on the screen changes in the next second
- Each of the 134 places, put into a copy of the code one at a time: `swift test` fails, or the `before` text of the change is no longer in its line, or `equivalent.md` names the change
- The README: one sentence for each fact of requirement 6
- The report of the pointer session: one line for each case of requirement 9, with the result

## Extras
- The joined emoji sequences (a skin tone, a joiner, a variation selector, a keycap mark, or a tag character joined into one wide cell): Terminal.app moves the cursor by the sum of the widths of the single characters (4 after U+1F44D U+1F3FD, 8 after the family, and 1 after U+2764 U+FE0F and after U+263A U+FE0F), and with the code removed, only tests of the join failed, and the real Claude Code session passed. The flag rule stays, because Terminal.app also moves 2 for a flag. Gone (#432).
- The removal of the wrap mark by `CSI J` at column 0: Terminal.app keeps the row joined to the next row, and with the code removed, each recording from Terminal.app passed and only the test of the removal failed. Gone (#433).
- The Powerline arrows (U+E0B0 to U+E0B3 drawn as shapes of the view): not measured in Terminal.app. With the code removed, only its own test failed. Stays until a measurement.

## Deviations
- Decision "after a measurement in Terminal.app": the permission system of the session denied the Terminal.app window of the worker, so the build made no new measurement there. The numbers of the emoji sequences and the row that stays joined come from the audit of 2026-11-15, which measured them in Terminal.app with cursor reports and with the text of the window. The Powerline arrows have no measurement, so they stay. What Terminal.app draws for a skin tone sequence and for a joiner sequence was not measured. TerminalKit now draws each character of such a sequence in its own cells: a thumb and a color square, and three faces for the family.
- Requirement 2: with the wrap rule gone, a wider window after output with no line break at its end shows a part of the prompt two times, as the audit saw in Terminal.app. Before, the screen stayed clean in that case.
- Requirement 1: the table of combined characters holds at most 65,536 entries. When it is full, the emulator builds it again from the cells of the screen, of the saved lines, and of the snapshot of synchronized output. When 65,536 combined characters still show, a new one keeps only the marks that its cell has, until as many new requests came and the table is built again. Terminal.app was not measured for this limit. One cell still holds up to 1,024 bytes, because Terminal.app keeps 257 marks on one cell (the recordings `w marks 32` to `w marks 257`). A full reset does not build the table again, because that reads each saved line for 2 bytes of input.
- Requirement 5, first sentence: not built. Terminal.app does not scroll at the last row after a resize makes the screen smaller than the scroll region (the recordings `rs region 2 10 h`, `rs region 2 10 h g`, and `rs region 2 10 cur` in `resize.json`), so the emulator keeps that behavior.
- Requirement 4: the selection and the copy, the links, and the text for VoiceOver still hold the cells past the last column of such a row, and the underline of such a link can show in the margin. They were not corrected, because no correction is one condition, and a program on the alternate screen draws again after a resize.
- Requirement 6 "`start()` throws only when the session has no view": the source differs. `start()` also starts the process at once, and throws, when the view already has its size. It waits only when a view exists that has no size yet. The README states this rule. For the saved lines, the README gives the measurement, 314 MB for 100,000 lines of 199 cells.
- Requirement 7: `TerminalContentView.drawCount` stays, because the speed test of requirement 9 of the first spec must prove that the view drew during the timed output of 100 MB (10 draws or more in each second). A view whose window is covered draws nothing and makes the time too short, and no other value of the product counts draws. The parameter `restoredRows` of `Terminal.resize` stays, because it is the only check of the number of saved rows that a resize restores (`resizesLikeARewrapOfEverySavedLine`).
- Requirement 10: the README has no line that says that a drop from the Finder works, so no line was added for it.
- Findings of the build that are not on the list, not corrected: the README lists dictation as an AppKit behavior, and dictation was not tested. Three quick Page Down presses during the scroll animation move less than three pages. The first Page Up after the app starts did not scroll when a worker posted the key to the app in the background (the pointer session looks at it with the app in front). An OSC whose name is not a number counts as OSC 0 and sets the title. `Terminal.resize` passes `rows + 1` as `restoredRows`, and each test also passes with `rows`.
