import AppKit
import SwiftUI
import TerminalCore
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalColorQueryTests {
    @Test(arguments: [(NSAppearance.Name.aqua, UInt16(0x0000), UInt16(0xFFFF)), (.darkAqua, 0xFFFF, 0x1E1E)])
    func reportsTheStandardPaletteInTheAppearanceOfTheView(
        appearance: NSAppearance.Name,
        foreground: UInt16,
        background: UInt16
    ) {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        view.appearance = NSAppearance(named: appearance)
        #expect(view.reportedColors == [gray(foreground), gray(background)])
    }

    @Test func reportsTheAppearanceOfTheWindow() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        #expect(view.reportedColors.count == 2)
        let window = NSWindow(contentView: view)
        window.appearance = NSAppearance(named: .darkAqua)
        #expect(view.reportedColors == [gray(0xFFFF), gray(0x1E1E)])
        window.appearance = NSAppearance(named: .aqua)
        #expect(view.reportedColors == [gray(0x0000), gray(0xFFFF)])
    }

    @Test func reportsThePalette() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        var palette = TerminalPalette.standard
        palette.foreground = Color(.sRGB, red: 1, green: 0, blue: 0)
        palette.background = Color(.sRGB, red: 0, green: 0, blue: 1)
        view.palette = palette
        #expect(
            view.reportedColors == [
                Terminal.RGB(red: 0xFFFF, green: 0, blue: 0), Terminal.RGB(red: 0, green: 0, blue: 0xFFFF),
            ]
        )
        palette.background = Color(nsColor: NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1))))
        view.palette = palette
        #expect(view.reportedColors.isEmpty)
    }

    @Test func answersTheColorQueriesInTheCurrentAppearance() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf a; head -c 1 >/dev/null; printf '\\033]11;?\\a\\033[c'; head -c 32 | tr '\\033' E"
        )
        let view = TerminalContentView(session: session)
        view.appearance = NSAppearance(named: .aqua)
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        view.appearance = NSAppearance(named: .darkAqua)
        session.send("x")
        await session.waitForExit()
        #expect(session.lines.contains("aE]11;rgb:1e1e/1e1e/1e1eE\\E[?1;2c"))
    }

    @Test func keepsTheColorsAfterTheSizingViewIsGone() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf a; head -c 1 >/dev/null; printf '\\033]11;?\\a\\033[c'; head -c 32 | tr '\\033' E"
        )
        let view = TerminalContentView(session: session)
        view.appearance = NSAppearance(named: .darkAqua)
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        session.sizingView = nil
        session.send("x")
        await session.waitForExit()
        #expect(session.lines.contains("aE]11;rgb:1e1e/1e1e/1e1eE\\E[?1;2c"))
    }

    @Test func changesTheTerminalOnceForEachOutputWhenTheColorsStayTheSame() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf a; head -c 1 >/dev/null; printf b; head -c 1 >/dev/null"
        )
        let view = TerminalContentView(session: session)
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        let revision = session.revision
        session.send("x")
        await session.waitForText("ab")
        #expect(session.revision == revision + 1)
        session.send("x")
        await session.waitForExit()
    }

    @Test func sendsNothingWhenTheAppearanceChanges() async throws {
        let session = TerminalSession(running: "stty raw -echo; printf '\\033[?2031ha'; head -c 1 | tr '\\033' E")
        let view = TerminalContentView(session: session)
        view.appearance = NSAppearance(named: .aqua)
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        view.appearance = NSAppearance(named: .darkAqua)
        session.send("x")
        #expect(await session.linesAfterExit().contains("ax"))
    }

    @Test func ignoresTheColorQueriesWithoutAView() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033]11;?\\a\\033[c'; head -c 7 | tr '\\033' E"
        )
        try session.start()
        await session.waitForExit()
        #expect(session.lines.contains("E[?1;2c"))
    }
}

private func gray(_ white: UInt16) -> Terminal.RGB {
    Terminal.RGB(red: white, green: white, blue: white)
}

@MainActor
struct TerminalWindowReportTests {
    @Test func reportsNoWindowAsHidden() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 197)
        #expect(view.windowReport == Terminal.WindowReport(width: 300, height: 197))
    }

    @Test func reportsTheWindowFromTheTopOfTheVisibleScreen() throws {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 197),
            styleMask: .titled,
            backing: .buffered,
            defer: true
        )
        window.contentView = view
        let hidden = view.windowReport
        #expect(!hidden.isVisible)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let screen = try #require(window.screen)
        #expect(
            view.windowReport
                == Terminal.WindowReport(
                    isVisible: true,
                    x: Int(window.frame.minX),
                    y: Int(screen.visibleFrame.maxY - window.frame.maxY),
                    width: 300,
                    height: 197
                )
        )
    }

    @Test func reportsTheScrollViewSize() {
        let scrollView = TerminalScrollView(session: TerminalSession(running: "exit"))
        scrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 197)
        scrollView.terminalView.frame = NSRect(x: 0, y: 0, width: 300, height: 5_000)
        #expect(scrollView.terminalView.windowReport == Terminal.WindowReport(width: 300, height: 197))
    }

    @Test func reportsHiddenAfterTheViewIsGone() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf a; head -c 1 >/dev/null; printf '\\033[11t\\033[c'; head -c 11 | tr '\\033' E"
        )
        let view = TerminalContentView(session: session)
        let window = NSWindow(contentView: view)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        #expect(session.terminal.windowReport.isVisible)
        session.sizingView = nil
        session.send("x")
        await session.waitForExit()
        #expect(session.lines.contains { $0.contains("E[2tE[?1;2c") })
    }

    @Test func answersTheWindowQueriesFromTheView() async throws {
        let session = TerminalSession(
            running: "stty raw -echo; printf '\\033[14t\\033[18t\\033[c'; head -c 26 | tr '\\033' E"
        )
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 197)
        session.sizingView = view
        try session.start()
        await session.waitForExit()
        #expect(session.lines.contains { $0.contains("E[4;197;300tE[8;") })
    }
}
