import AppKit
import SwiftUI
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalColorSchemeTests {
    @Test func reportsTheChangeToALightBackground() async throws {
        let session = asking(for: "dd bs=1 count=9 2>/dev/null | od -An -tx1")
        let view = try await startedView(of: session)
        view.palette = lightPalette
        #expect(await session.linesAfterExit().contains("1b  5b  3f  39  39  37  3b  32  6e"))
    }

    @Test func reportsTheChangeToADarkBackground() async throws {
        let session = asking(for: "dd bs=1 count=9 2>/dev/null | od -An -tx1")
        let view = try await startedView(of: session, palette: lightPalette)
        view.palette = .standard
        #expect(await session.linesAfterExit().contains("1b  5b  3f  39  39  37  3b  31  6e"))
    }

    @Test func reportsNothingInsideTheSameClass() async throws {
        let session = asking(for: "dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = try await startedView(of: session)
        var palette = TerminalPalette.standard
        palette.background = .black
        view.palette = palette
        session.send("a")
        #expect(await session.linesAfterExit().contains("61"))
    }

    @Test func reportsNothingWhenTheProcessDoesNotAsk() async throws {
        let session = TerminalSession(running: "stty raw -echo; echo ready; dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        session.sizingView = view
        try session.start()
        await session.waitForText("ready")
        view.palette = lightPalette
        session.send("a")
        #expect(await session.linesAfterExit().contains("61"))
    }

    @Test func reportsNothingWhenTheProcessSetsTheMode() async throws {
        let session = asking(for: "dd bs=1 count=1 2>/dev/null | od -An -tx1")
        let view = TerminalContentView(session: session)
        view.palette = lightPalette
        session.sizingView = view
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesColorSchemeReporting }) where isEnabled {
            break
        }
        session.send("a")
        #expect(await session.linesAfterExit().contains("61"))
    }

    @Test func reportsNothingAfterTheProcessEnds() async throws {
        let session = asking(for: "true")
        let view = try await startedView(of: session)
        await session.waitForExit()
        view.palette = lightPalette
        #expect(session.state == .exited(.exit(0)))
    }

    @Test func answersTheColorQueryWithTheNewColor() async throws {
        let session = asking(for: queryAfterReport)
        let view = try await startedView(of: session)
        view.palette = lightPalette
        #expect(await session.linesAfterExit().contains { $0.contains("]11;rgb:ffff/ffff") })
    }

    @Test func reportsTheChangeOfThePaletteOfTheHost() async throws {
        let session = asking(for: queryAfterReport)
        let hostingView = NSHostingView(rootView: TerminalView(session: session).terminalPalette(.standard))
        let window = NSWindow(contentView: hostingView)
        hostingView.layoutSubtreeIfNeeded()
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesColorSchemeReporting }) where isEnabled {
            break
        }
        hostingView.rootView = TerminalView(session: session).terminalPalette(lightPalette)
        hostingView.layoutSubtreeIfNeeded()
        #expect(await session.linesAfterExit().contains { $0.contains("]11;rgb:ffff/ffff") })
        #expect(window.contentView === hostingView)
    }

    private var queryAfterReport: String {
        "head -c 9 >/dev/null; printf '\\033]11;?\\033\\\\'; head -c 18 | tr '\\033' E"
    }

    private var lightPalette: TerminalPalette {
        var palette = TerminalPalette.standard
        palette.foreground = .black
        palette.background = .white
        return palette
    }

    private func asking(for command: String) -> TerminalSession {
        TerminalSession(running: "stty raw -echo; printf '\\033[?2031h'; \(command)")
    }

    private func startedView(
        of session: TerminalSession,
        palette: TerminalPalette = .standard
    ) async throws -> TerminalContentView {
        let view = TerminalContentView(session: session)
        view.palette = palette
        session.sizingView = view
        try session.start()
        for await isEnabled in Observations({ session.liveTerminal.usesColorSchemeReporting }) where isEnabled {
            break
        }
        return view
    }
}
