# Tight code and proofs

Status: accepted

## Goal
The first spec, `specs/terminal-for-agent-tools.md`, is reached: its 13 requirements pass, and a compare with Terminal.app found no open defect. But the code holds more than the owner wants. The README states an aim, "as well as in the best Mac terminals", that no test measures, and work toward that aim added behaviors that Terminal.app does not have, with no proof that they are needed. No test finds 30 of 200 single changes of the emulator, so that code is not needed or not protected. Some behaviors were never proven. This spec ends the work: it sets the measure at Terminal.app, makes each extra prove its need or go, settles each of the 30 changes, proves what an automatic test can prove, and names the rest. It affects the README, the code and the tests in `Sources` and `Tests`, the first spec, and the branches of the repository.

## Decisions
- The measure of done is that the listed programs work at least as well as in Terminal.app, and that the host app also gets the status that a program reports. The aim "as well as in the best Mac terminals" ends. It is the choice most likely to change first.
- An extra is a behavior that TerminalKit has and Terminal.app does not have. An extra stays only when a removal test proves that it is needed. That a program uses it is not a proof.
- The status that a program reports (OSC 7501, `programStatus`) stays with no removal test, because the host app of the owner needs it.
- Marked links (OSC 8, with their tooltip and `FORCE_HYPERLINK=1`) and the theme report (mode 2031) take the removal test as each other extra does. The owner expects that they go.
- No program joins the list, and the host gets no new API. Codex, tmux, ssh, the exit status, a restart of a session, the screen text, and the shell pid wait for a later spec.
- The cleanup removes each branch apart from `main` and each worktree apart from the main checkout.
- A removal test proves the need when, with the code of the extra removed, a requirement of the first spec fails as the tag 2.0.0 states it, with its Deviations, or a step of the fixed script of a listed program fails. A test that only tests the extra itself proves nothing (assumed)
- Tight is measured by the 200 single changes of the mutation test of 2026-11-13, not by a new sample (assumed)
- A proof that needs a person stays out, because the owner does no manual test, and a worker does not move the real pointer, start voice input, or change a system setting. The README says "not tested" only where one of its lines says that the thing works (assumed)
- The owner tags 2.1.0 when each requirement passes, because `programStatus` is new public API (assumed)

## Requirements
1. The first paragraph of the README states the aim: the listed programs work at least as well as in Terminal.app, and the host app also gets the status that a program reports. No line of the README claims the level of another terminal.
2. This spec holds a section `Extras` with one line for each extra: what it is, what failed with its code removed, and whether it stays. The list comes from a measurement in Terminal.app of each control function, mode, and query that TerminalKit acts on, each key that it sends in a different way, each environment variable that it sets, and each thing that a person can do in the view.
3. Each extra whose removal test did not prove the need is gone from `Sources`, and the tests that only test it are gone with it.
4. After the removals, the README, the first spec, and the lists of acted and ignored sequences in `ProgramSessionTests` say the same as the code. The first spec holds one Deviation line that says that the measure changed, and names this spec.
5. For each of the 30 changes with the result `none` in `.claude/e2e-tools/mutation/results.jsonl`, one of these is true: a test fails when the change is in the code; the code that the change touches is gone; or `.claude/e2e-tools/mutation/equivalent.md` names the change with the reason why no test can find it. A reason is that no program and no person can observe the difference, or that only a failed system call reaches the code.
6. In the fullscreen mode of a real Claude Code session, in a window that hosts the view, a double click selects a word and a triple click selects a line.
7. The README states what macOS shows when Claude Code asks for attention in a host that has no grant to control Terminal.app, from a measurement with a host that has the hardened runtime and with one that does not.
8. The README says that voice input was not tested.
9. On GitHub and in the clone, `main` is the only branch, and the main checkout is the only worktree. A branch or a worktree goes only after a check that `main` holds its work, or that its work was a trial. One that fails the check stays, and Deviations names it. No process and no window of a worker stays.

## Edge cases
Each one needs a test.
- None. Each case follows from a requirement.

## Out of scope
- A notification event for the host, the extended keyboard protocol, and trackpad scroll by distance
- Codex, tmux, ssh, and new host API
- A new sample of single changes, and a mutation test in the repository or in CI
- Proof with a real pointer, a real press of a dead key, a real input method, Screen Curtain, and voice input
- The tag, which the owner makes

## Constraints
- Reference: `Tests/TerminalCoreTests/ProgramStatusTests.swift`, which gives bytes to the emulator and compares values
- Remove an extra by a revert of the pull request that added it, when one exists, so that its tests and its text go with it. For marked links that is #386, and for the theme report #385
- The removal test of an extra runs the full tests, the real Claude Code session in the window, and the speed tests
- Code goes only by the rule of the first spec: no listed program needs it, no person uses it in the view, it does not keep bad input from causing a crash or a hang, and the host app does not need it
- No change to the product code only to make a test possible
- The repository gets no new tool and no new list file. The mutation files stay in `.claude/e2e-tools/mutation`, outside Git
- No dependencies, macOS 27, Swift 6 strict concurrency, and no change to the user's shell startup files
- No press of a button of a macOS permission prompt. A prompt that shows during a measurement stays, and the report names it first
- When the permission system blocks a deletion, that item stops, the owner gets the exact command, and Deviations names it
- Each pull request is small, uses the repository template, and merges only after CI passes

## Check
- `swift format lint --recursive --strict Package.swift Sources Tests Example`: no output
- `xcodebuild test -scheme TerminalKit -destination 'platform=macOS'`: `** TEST SUCCEEDED **`
- `xcodebuild build` for the scheme of the example app: `** BUILD SUCCEEDED **` and no warning
- `TERMINALKIT_CLAUDE_SESSION=1 Scripts/unused-functions.sh`: exit status 0, the line `The real Claude Code session ran`, and a last line that ends with `unused ones is on the list`
- `TERMINALKIT_SPEED=1 swift test -c release -Xswiftc -enable-testing --filter SpeedTests`: the two tests pass
- `grep -c "best Mac terminals" README.md`: `0`
- For each line of the section `Extras` that says that the extra is gone: its bytes, sent to the emulator, change nothing and get no reply
- Each of the 30 changes, put into a copy of the code one at a time: `swift test` fails, or the `before` text of the change is no longer in its file, or `equivalent.md` names the change
- `git ls-remote --heads origin`: one line, which ends with `refs/heads/main`
- `git branch --format='%(refname:short)'`: only `main`
- `git worktree list`: one line
- In a window that hosts the view, in Claude Code with `CLAUDE_CODE_NO_FLICKER=1`, double-click a word of an answer, then triple-click a line: Claude Code shows the word, then the line, as selected

## Extras

## Deviations
