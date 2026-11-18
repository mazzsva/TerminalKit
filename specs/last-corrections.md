# Last corrections

Status: accepted

## Goal
The three specs are built, and the tag `2.2.0` is made. The Deviations of `specs/closing-list.md` and the README still name findings that nobody corrected, behaviors that nobody measured in Terminal.app, and input paths that nobody tested. The owner wants a clean project. So each of them gets a correction, a measurement, or a test, and then the README and the specs say what is true. This list is closed. After it, the end rule of `specs/closing-list.md` applies again.

## Decisions
- The orchestrator owns this list and decides each item.
- The owner runs one script by hand for the measurements in Terminal.app, because the permission system of the session denies a Terminal.app window to the workers.
- One session with the real pointer and the real keyboard runs after the owner says that the owner is away from the Mac.
- Codex, tmux, and ssh stay out of the list of programs.
- Where a measurement shows that Terminal.app does the same as TerminalKit, nothing changes, and this spec says so. Where it differs, TerminalKit changes to what Terminal.app does.
- In the saved lines, one line of a wheel moves the view one row, as on the alternate screen. Terminal.app is not measured for this, because nothing may send a wheel event to Terminal.app. (assumed)
- The view treats a screen row as its first cells up to the last column in each path, because that is what it draws. (assumed)
- A start of voice input stays out, because the rules of the project forbid it. (assumed)
- The 101 named places of requirement 8 of the closing list get no new test. (assumed)

## Requirements
1. In the saved lines, 1, 2, and 3 lines of a wheel that gives line steps move the view 1, 2, and 3 rows.
2. Each scroll that the view starts moves at once. This includes the correction of the position after saved lines go away at the limit, and the scroll to a result of the find bar.
3. The copy, the selection, the links, the find bar, and the text for VoiceOver hold no cell past the last column of a screen row.
4. The function that lays out the screen again after a resize takes a cursor that is not optional.
5. The count of saved rows that a resize restores has a proof: a test fails with the other value, or a written proof shows that the two values give the same result.
6. A test sets a palette color in the `rgb:` form that the terminfo entry holds, and it fails without that code.
7. The test `readsTheRowsOfALongWideSavedLineQuickly` passes while other work loads the Mac, and it fails with the slow code.
8. Each function and each branch of the text input code has a test that fails without it, or it is gone.
9. An OSC whose name is not a number does what Terminal.app does, and the emulator has no code for it that no input gets to.
10. After a resize, a wrap that waits at the last column, the mark of a moved cursor, and the cursor after a change of the columns only do what Terminal.app does.
11. U+E0A0 to U+E0A3 show as symbols, as in Terminal.app.
12. For a skin tone sequence and a joiner sequence, the view draws what Terminal.app draws.
13. In the session with the real pointer and keyboard: a drop of a file from the Finder puts its path on the input line, a Command-click opens a web link, the accent menu inserts the accented letter in an app that has press and hold on, an input method that is already on composes text, and each pointer case of the closing list has a result file.
14. The README, the four specs, and the private lists agree with the code. Each line that still says "not tested" or "not measured" gives the reason.
15. A fresh verifier passes each requirement, and the full verification passes on the final code.

## Edge cases
Each one needs a test.
- A trackpad, and a wheel with precise steps: the view moves as before.
- A change of the font: one line of the wheel still moves one row.
- A link whose text crosses the last column after the window gets narrower: no underline past the last column.
- The saved lines after the window gets narrower: the copy holds each character, because the emulator lays them out again.

## Out of scope
- Codex, tmux, ssh, and a new host API
- A start of voice input
- A compare of the wheel, of the scroll keys, and of the pointer cases with Terminal.app
- A new test for a named place of requirement 8 of the closing list
- A new audit, a new sample of single changes, and a measurement that this spec does not name
- The tag, which the owner makes

## Constraints
- Reference: `specs/closing-list.md`, and the rules of `specs/tight-code-and-proofs.md` for an extra and for the removal test
- No change to the public API
- No change to the product code only to make a test possible
- Terminal.app is the reference in both directions

## Check
- `swift format lint --recursive --strict Package.swift Sources Tests Example`: no output
- `xcodebuild test -scheme TerminalKit -destination 'platform=macOS'`: `** TEST SUCCEEDED **`, and no compiler warning
- `Scripts/unused-functions.sh` with the real Claude Code session: each unused function is on the list
- The speed tests: the output of 100 MB is no slower than in Terminal.app
- In the example app, `printf '\356\202\240 \356\202\260\n'`: a branch symbol and an arrow, and no "?" box

## Deviations
- Requirement 5: the two values differ, and no reference decides between them, so the code stays. With `rows` in place of `rows + 1`, each test passes, and 3,000 random runs with text that shows found no difference. The values differ only in how many cells of a blank row with a background color a saved row keeps after two resizes, and in the count of saved lines for a screen of one row, which the view never sets. A full layout of each saved line gives a third result. A taller window makes the three results the same, so a picture of Terminal.app can not show the case with no scroll of its window.
- Requirement 8: 71 single changes of the text input code, of which 70 built, 21 with no test before. 14 have a test now. The code of 5 is gone: the check for marked text and two branches in the choice of the key bytes, a second clear of the marked text, and a reset for keys that send nothing. One stays with no test: the index of the character at a point, which is 0, the smallest form that the protocol permits. The only case that the check for marked text changed was a Korean layout with Option as the Meta key, and nobody tested it with a real input method. The 14 tests, the 5 removals, and the 1 place that stays are 20 of the 21, and the report of the build does not say where the last one went.
- Requirement 9: the finding of the closing list was false. The parser drops an OSC whose name is not a number, so it never set the title. The code that no input got to is gone (#467). Terminal.app sets the title for an OSC with an empty name, and for a name with a letter it prints the rest of the sequence as text. TerminalKit drops both, and this stays, because no listed program sends them and the second is a quirk.
- Requirement 3: a link that the last column cuts is the text that shows, so a Command-click opens that shorter text. Terminal.app differs for the text, and TerminalKit does not follow it here. Measured on 2026-11-18 on the alternate screen, with a row of 40 characters and a window that got 20 columns wide: Select All and Copy in Terminal.app gives all 40 characters, and its text for Accessibility holds all 40, but its window shows 20 and draws a part of the next ones in the padding at the right edge. TerminalKit copies and reads the 20 characters that it draws. After the program erases the rest of that row, the hidden characters move into view in both terminals, and the two draw the same 20 cells. After the program clears the screen, as each listed program does after a resize, both give the same text. The owner decided that TerminalKit follows Terminal.app unless what Terminal.app does is wrong or weird. A copy of text that the window does not show counts as weird, so the view keeps the rule of this requirement. The find bar of Terminal.app was not measured for this, because the session had no case for it.
- Requirement 1: AppKit moves the view for a wheel with an animation. A test did not check new output during that animation.
- Requirement 10: measured in Terminal.app with 35 cases, which the build ran with one script. The cursor after a change of the columns only is the same in both (3 widths), so nothing changed. A wrap that waits gives the same cursor reports in both, but TerminalKit kept blank cells in the text of the line before the next character, and that is corrected (#470). For a full last row, Terminal.app has this rule: when the cursor is on that row or saved lines come back, the row gets an empty row after it, and if not, the cursor moves one column right. TerminalKit kept a mark from the resize before in place of that rule, and it gave another cursor in 7 of 24 cases. The rule replaces the mark (#468), and the 24 cases are a recording in the tests.
- Requirement 11: the view draws the branch symbol and the lock as shapes, and the two letter pairs with the font of the view at half size. Against the picture of Terminal.app, 74% to 89% of the ink is in the same place.
- Requirement 12: the view draws a skin tone sequence, a joiner sequence, a keycap, and a tag sequence as one glyph at the first cells, as the picture of Terminal.app shows. The emulator did not change. An earlier measurement (#284) said that Terminal.app keeps joiner and tag sequences apart and joins a letter with U+20E3. The new picture shows the first two joined, and a letter with U+20E3 was not measured again and stays apart.
- Decision "the owner runs one script by hand": the owner told the build to run the script, and the permission system permitted it, so the build ran it.
- Requirement 13: the session ran one time, on 2026-11-18, with the real pointer and the real keyboard, and with one run of each case. Each of the 13 pointer cases of the closing list worked, and each has a result file. A file that a person drags from the Finder puts its path on the input line, with a backslash before a space and no Return. A Command-click on a printed web link opens it in the browser, and a click with no Command opens nothing. With press and hold on, a held E shows the accent menu and one `e`, and a number key puts the accented letter in place of the `e`. One defect: Escape did not close the accent menu, and the view sent ESC to the program. It is corrected with a test (#474): while the text of the last key can still be replaced, a key with no modifier goes to the input system first. No input method was tested, because no input method is on on the Mac of the session, and the build turns none on. A dead key was tested in its place: Option-E shows the accent as marked text, and E then gives `é`. The result files and the pictures show private data, so they are not in the repository.
- Requirement 14: the README now says that the view draws U+E0A0 to U+E0A3, what the session with the real keyboard tested and why it tested no input method, no dictation, and no voice input, and it names the OSC with an empty name as a known limit. The three older specs keep their text, and a sentence at the end of each line that later work made false, or that said "not measured" with no reason, names the change and its pull request or this spec.
- Edge case "a trackpad, and a wheel with precise steps": the build had no test for it in the saved lines. The fresh verifier found that, and a test is there now.
- Requirement 15: a fresh verifier checked the final code on 2026-11-18. 13 of 15 requirements, 3 of 4 edge cases, and 4 of 5 Check lines passed. The Check line with the example app passed only in part: the verifier read the text of the window and drew the view off screen, and took no picture of the window, because another window covered it. Requirement 14 failed by one false sentence in `specs/closing-list.md` (not each suite of the view tests has a time limit of 3 minutes), and the first edge case failed by the missing test. Both are corrected, with two smaller faults that the verifier named: the README sentence on `CLAUDE_CODE_FORCE_SYNC_OUTPUT`, and two numbers in these Deviations. The same verifier then checked the corrections. No second fresh verifier ran. The full verification passed on the code before these corrections, which change no product code: 936 tests, no compiler warning, each unused function on the list with the real Claude Code session, and the output of 100 MB in 0.94 of the time of Terminal.app.
