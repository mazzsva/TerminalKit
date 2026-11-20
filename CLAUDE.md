# TerminalKit

A Swift package with no dependencies. `Sources/TerminalCore` holds the emulator and the pseudo terminal, `Sources/TerminalKit` holds the AppKit view, and `Example` holds the example app.

# Running the Checks
- Lint with `swift format lint --recursive --strict Package.swift Sources Tests Example`; no output means that it passed
- Run the full tests with the `TerminalKit` scheme for My Mac; in Xcode, open the package folder, because the example project has no test bundles for that scheme
- The xcodebuild form is `xcodebuild test -scheme TerminalKit -destination 'platform=macOS'`, in the package folder
- Build the example app with the `TerminalKitExample` scheme of `Example/TerminalKitExample.xcodeproj`
- Xcode cannot hold the package folder and the example project open at the same time, so close one before you open the other
- Run `Scripts/unused-functions.sh` after you add or remove a function in `Sources`, because CI does not run it
- Run one test run at a time, because the tests use pseudo terminals and time limits, and runs at the same time made them fail

# Known Problems
- A process that you start gets the `CLAUDE` variables of your session; remove them before you start the example app or the real Claude Code tests, but keep `CLAUDE_CODE_FORCE_SYNC_OUTPUT`
- The two real Claude Code tests run only with `TERMINALKIT_CLAUDE_SESSION=1`; without it they report that they did not run
- A test can fail by its time limit when other work loads the Mac, or when a CI runner is slow; run it again one time, and find the cause when the same test fails a second time
- `ReadmeTests` compares the README with `Tests/TerminalKitTests/ReadmeExample.swift` and with the ignored sequences of `ProgramSessionTests`, so change them together
- The README states facts that no test checks, such as the number of lines and the number of behaviors that Terminal.app does not have; check them when a change touches them

# Rules of the Project
- Terminal.app is the reference; before you add or remove a behavior, read the Decisions of `specs/tight-code-and-proofs.md`
- The repository is public, so put no name, email, computer name, or path of this Mac in a file, a commit, or a pull request, and no picture or recording of a real session
- The specs in `specs` are in Git; commit a spec with the change that it describes
