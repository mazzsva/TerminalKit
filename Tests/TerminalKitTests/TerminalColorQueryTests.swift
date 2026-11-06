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
        #expect(view.reportedColors?.foreground == gray(foreground))
        #expect(view.reportedColors?.background == gray(background))
    }

    @Test func reportsTheAppearanceOfTheWindow() {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        #expect(view.reportedColors != nil)
        let window = NSWindow(contentView: view)
        window.appearance = NSAppearance(named: .darkAqua)
        #expect(view.reportedColors?.foreground == gray(0xFFFF))
        #expect(view.reportedColors?.background == gray(0x1E1E))
        window.appearance = NSAppearance(named: .aqua)
        #expect(view.reportedColors?.foreground == gray(0x0000))
        #expect(view.reportedColors?.background == gray(0xFFFF))
    }

    @Test func reportsThePalette() throws {
        let view = TerminalContentView(session: TerminalSession(running: "exit"))
        var palette = TerminalPalette.standard
        palette.foreground = Color(.sRGB, red: 1, green: 0, blue: 0)
        palette.background = Color(.sRGB, red: 0, green: 0, blue: 1)
        palette.cursor = Color(.sRGB, red: 0, green: 1, blue: 0)
        palette.selection = Color(.sRGB, red: 1, green: 1, blue: 0)
        palette.ansiColors[1] = Color(.sRGB, red: 0, green: 1, blue: 1)
        view.palette = palette
        let colors = try #require(view.reportedColors)
        #expect(colors.foreground == Terminal.RGB(red: 0xFFFF, green: 0, blue: 0))
        #expect(colors.background == Terminal.RGB(red: 0, green: 0, blue: 0xFFFF))
        #expect(colors.cursor == Terminal.RGB(red: 0, green: 0xFFFF, blue: 0))
        #expect(colors.selection == Terminal.RGB(red: 0xFFFF, green: 0xFFFF, blue: 0))
        #expect(colors.bold == colors.foreground)
        #expect(colors.ansi[1] == Terminal.RGB(red: 0, green: 0xFFFF, blue: 0xFFFF))
        palette.background = Color(nsColor: NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1))))
        view.palette = palette
        #expect(view.reportedColors == nil)
    }

    @Test func answersTheColorQueriesInTheCurrentAppearance() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf a; head -c 1 >/dev/null; printf '\\033]11;?\\a\\033[c'; head -c 31 | tr '\\033' E"
        )
        let view = TerminalContentView(session: session)
        view.appearance = NSAppearance(named: .aqua)
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        view.appearance = NSAppearance(named: .darkAqua)
        session.send("x")
        await session.waitForExit()
        #expect(session.lines.contains("aE]11;rgb:1e1e/1e1e/1e1eE[?1;2c"))
    }

    @Test func keepsTheColorsAfterTheSizingViewIsGone() async throws {
        let session = TerminalSession(
            running:
                "stty raw -echo; printf a; head -c 1 >/dev/null; printf '\\033]11;?\\a\\033[c'; head -c 31 | tr '\\033' E"
        )
        let view = TerminalContentView(session: session)
        view.appearance = NSAppearance(named: .darkAqua)
        session.sizingView = view
        try session.start()
        await session.waitForText("a")
        session.sizingView = nil
        session.send("x")
        await session.waitForExit()
        #expect(session.lines.contains("aE]11;rgb:1e1e/1e1e/1e1eE[?1;2c"))
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

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalChangedColorTests {
    private func view(after output: String) async throws -> TerminalContentView {
        let session = TerminalSession(running: "printf '\(output)'; sleep 30")
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        session.sizingView = view
        try session.start()
        await session.waitForText("X")
        return view
    }

    private func pixel(at point: CGPoint, of view: NSView) throws -> NSColor {
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let scale = CGFloat(representation.pixelsWide) / representation.size.width
        return try #require(
            representation.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        )
    }

    private func isColor(
        at point: CGPoint,
        of view: TerminalContentView,
        red: Int,
        green: Int,
        blue: Int
    ) throws -> Bool {
        let drawn = try pixel(at: point, of: view)
        let palette = view.palette
        defer { view.palette = palette }
        let changes = view.session.terminal.changedColors
        guard changes.background == nil, !view.session.terminal.usesReverseVideo else {
            return abs(Int((drawn.redComponent * 255).rounded()) - red) <= 1
                && abs(Int((drawn.greenComponent * 255).rounded()) - green) <= 1
                && abs(Int((drawn.blueComponent * 255).rounded()) - blue) <= 1
        }
        view.palette.background = Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
        let expected = try pixel(at: CGPoint(x: view.bounds.maxX - 1, y: view.bounds.maxY - 1), of: view)
        return abs(drawn.redComponent - expected.redComponent) < 0.01
            && abs(drawn.greenComponent - expected.greenComponent) < 0.01
            && abs(drawn.blueComponent - expected.blueComponent) < 0.01
    }

    @Test func drawsTheChangedBackground() async throws {
        let view = try await view(after: "\\033]11;#102030\\aX")
        defer { view.session.terminate() }
        #expect(try isColor(at: CGPoint(x: 150, y: 80), of: view, red: 0x10, green: 0x20, blue: 0x30))
    }

    @Test func drawsTheChangedIndexedBackgrounds() async throws {
        let view = try await view(
            after: "\\033]4;1;#102030;200;#405060\\a\\033[41m  \\033[48;5;200m  \\033[mX"
        )
        defer { view.session.terminate() }
        let y = view.cellSize.height / 2
        let first = CGPoint(x: view.cellSize.width, y: y)
        let second = CGPoint(x: view.cellSize.width * 3, y: y)
        #expect(try isColor(at: first, of: view, red: 0x10, green: 0x20, blue: 0x30))
        #expect(try isColor(at: second, of: view, red: 0x40, green: 0x50, blue: 0x60))
    }

    @Test func drawsThePaletteAgainAfterAReset() async throws {
        let view = try await view(after: "\\033]11;#102030\\a\\033]111\\aX")
        defer { view.session.terminate() }
        #expect(!(try isColor(at: CGPoint(x: 150, y: 80), of: view, red: 0x10, green: 0x20, blue: 0x30)))
    }

    @Test func redrawsAfterEachChange() async throws {
        let session = TerminalSession(
            running: "printf '\\033]11;#102030\\aX'; read a; printf '\\033]11;#405060\\aY'; sleep 30"
        )
        let view = TerminalContentView(session: session)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        session.sizingView = view
        defer { session.terminate() }
        try session.start()
        await session.waitForText("X")
        let point = CGPoint(x: 150, y: 80)
        #expect(try isColor(at: point, of: view, red: 0x10, green: 0x20, blue: 0x30))
        session.send("\n")
        await session.waitForText("Y")
        #expect(try isColor(at: point, of: view, red: 0x40, green: 0x50, blue: 0x60))
    }

    @Test func drawsTheChangedForeground() async throws {
        let view = try await view(after: "\\033]10;#102030\\a\\033[7m  \\033[mX")
        defer { view.session.terminate() }
        let point = CGPoint(x: view.cellSize.width, y: view.cellSize.height / 2)
        #expect(try isColor(at: point, of: view, red: 0x10, green: 0x20, blue: 0x30))
    }

    @Test func swapsTheChangedColorsInReverseVideo() async throws {
        let view = try await view(after: "\\033]10;#102030\\a\\033]11;#405060\\a\\033[?5hX")
        defer { view.session.terminate() }
        #expect(try isColor(at: CGPoint(x: 150, y: 80), of: view, red: 0x10, green: 0x20, blue: 0x30))
    }

    @Test func drawsTheChangedSelection() async throws {
        let session = TerminalSession(running: "printf '\\033]17;#102030\\aX'")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        await session.waitForExit()
        view.selection = TerminalContentView.Selection(
            anchor: .init(line: 0, column: 2),
            head: .init(line: 0, column: 8)
        )
        #expect(window.firstResponder === view)
        let point = CGPoint(x: 4 + view.cellSize.width * 5.5, y: 4 + view.cellSize.height / 2)
        #expect(try isColor(at: point, of: view, red: 0x10, green: 0x20, blue: 0x30))
    }

    @Test func drawsTheChangedCursor() async throws {
        let session = TerminalSession(running: "printf '\\033]12;#102030\\aX'")
        let view = TerminalContentView(session: session)
        let window = KeyWindow(contentView: view)
        view.palette.cursor = Color(.sRGB, red: 1, green: 1, blue: 1)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        try session.start()
        await session.waitForExit()
        #expect(window.firstResponder === view)
        let point = CGPoint(x: view.cursorRect.midX, y: view.cursorRect.midY)
        #expect(try isColor(at: point, of: view, red: 0x10, green: 0x20, blue: 0x30))
    }
}
