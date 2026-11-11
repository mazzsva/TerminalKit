import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.enabled(if: isReleaseBuild && ProcessInfo.processInfo.environment["TERMINALKIT_SPEED"] != nil), .serialized)
struct SpeedTests {
    @Test(.timeLimit(.minutes(5)))
    func outputsAHundredMegabytes() async throws {
        let file = URL.temporaryDirectory.appending(path: "SpeedTests-" + UUID().uuidString + ".txt")
        let widths = try writeText(to: file, byteCount: 100_000_000)
        defer { try? FileManager.default.removeItem(at: file) }

        var viewTimes: [Duration] = []
        var drawCounts: [Int] = []
        var sessionTimes: [Duration] = []
        var bytesPerLine = 0
        var peakMemory = 0
        let footprint = memoryFootprint()
        for _ in 0 ..< 5 {
            let session = catSession(file)
            let (scrollView, window) = shownView(session)
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            viewTimes.append(try await time(session))
            let drawCount = scrollView.terminalView.drawCount
            drawCounts.append(drawCount)
            #expect(Double(drawCount) >= 10 * (viewTimes[viewTimes.count - 1] / .seconds(1)))
            scrollView.layoutSubtreeIfNeeded()
            let terminal = session.terminal
            let rows = widths.reduce(1) { $0 + max(1, ($1 + terminal.columns - 1) / terminal.columns) }
            #expect(session.state == .exited(.exit(0)))
            #expect(terminal.removedScrollbackCount + terminal.scrollback.count + terminal.rows == rows)
            #expect(session.lines.suffix(2) == ["end of the text", ""])
            if viewTimes.count == 1 {
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                peakMemory = usage.ru_maxrss
                bytesPerLine = (memoryFootprint() - footprint) / terminal.scrollback.count
            }
            #expect(window.contentView === scrollView)
            #expect(window.isVisible && !window.isKeyWindow)
        }
        for _ in 0 ..< 5 {
            let session = catSession(file)
            sessionTimes.append(try await time(session))
            #expect(session.lines.suffix(2) == ["end of the text", ""])
        }

        let viewTime = median(viewTimes)
        print(
            """
            Output of 100 MB with a view: \(viewTimes), median \(viewTime), \(Int(100 / (viewTime / .seconds(1)))) MB/s
            Draws during the output with a view: \(drawCounts)
            Output of 100 MB with no view: \(sessionTimes), median \(median(sessionTimes))
            Peak memory after the first output: \(peakMemory / 1_000_000) MB, bytes for each saved line: \(bytesPerLine)
            """
        )
        #expect(viewTime <= .milliseconds(5_000))
    }

    @Test(.timeLimit(.minutes(2)))
    func resizesAHundredThousandSavedLines() async throws {
        let session = TerminalSession(running: "true")
        let (scrollView, window) = shownView(session)
        let view = scrollView.terminalView
        var index = 0
        while session.liveTerminal.removedScrollbackCount == 0 {
            var text = ""
            for _ in 0 ..< 1000 {
                text += line(index) + "\r\n"
                index += 1
            }
            _ = session.liveTerminal.receive(Array(text.utf8))
        }
        scrollView.layoutSubtreeIfNeeded()
        view.scrollToBottom()

        let columns = session.terminal.columns
        var times: [Duration] = []
        for step in 1 ... 8 {
            let clock = ContinuousClock()
            let start = clock.now
            let width = window.contentLayoutRect.width + (step.isMultiple(of: 2) ? 1 : -1) * view.cellSize.width
            window.setContentSize(CGSize(width: width, height: window.contentLayoutRect.height))
            scrollView.layoutSubtreeIfNeeded()
            let visible = view.visibleRect
            view.cacheDisplay(in: visible, to: try #require(view.bitmapImageRepForCachingDisplay(in: visible)))
            times.append(clock.now - start)
            #expect(session.terminal.columns == (step.isMultiple(of: 2) ? columns : columns - 1))
            #expect(session.terminal.scrollback.count > 99_000)
            #expect(visible.height > 20 * view.cellSize.height && visible.maxY == view.bounds.maxY)
        }
        print(
            """
            Resize of the view with \(session.terminal.scrollback.count) saved lines: \(times), \
            median \(median(times)), slowest \(times.max() ?? .zero)
            """
        )
        #expect(try #require(times.max()) < .milliseconds(100))
    }

    private func shownView(_ session: TerminalSession) -> (TerminalScrollView, NSWindow) {
        let scrollView = TerminalScrollView(session: session)
        let view = scrollView.terminalView
        let window = NSWindow(contentView: scrollView)
        window.setContentSize(
            CGSize(
                width: 80.5 * view.cellSize.width + 2 * TerminalContentView.padding + 20,
                height: 24 * view.cellSize.height + TerminalContentView.topPadding + TerminalContentView.bottomPadding
            )
        )
        scrollView.layoutSubtreeIfNeeded()
        return (scrollView, window)
    }

    private func catSession(_ file: URL) -> TerminalSession {
        TerminalSession(
            configuration: .init(
                executableURL: URL(filePath: "/bin/cat"), arguments: [file.path(percentEncoded: false)])
        )
    }

    private func time(_ session: TerminalSession) async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        try session.start()
        await session.waitForExit()
        return clock.now - start
    }

    private func writeText(to file: URL, byteCount: Int) throws -> [Int] {
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var widths: [Int] = []
        var written = 0
        var index = 0
        while written < byteCount {
            var chunk = ""
            while chunk.utf8.count < 1_000_000 {
                let (text, width) = textLine(index)
                chunk += text + "\n"
                widths.append(width)
                index += 1
            }
            try handle.write(contentsOf: Data(chunk.utf8))
            written += chunk.utf8.count
        }
        try handle.write(contentsOf: Data("end of the text\n".utf8))
        widths.append(15)
        return widths
    }

    private func textLine(_ index: Int) -> (String, Int) {
        if index % 10 == 0 {
            let text = "\(index) 日本語のテキスト"
            return (text, text.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 2) })
        }
        let text = String(
            String(repeating: "\(index) The quick brown fox jumps over the lazy dog. ", count: 5)
                .prefix((index * 7919) % 200))
        return (text, text.count)
    }

    private func line(_ index: Int) -> String {
        switch index % 4 {
        case 0:
            "short \(index)"
        case 1:
            String(repeating: "wrapped line \(index) ", count: 12)
        case 2:
            String(repeating: "mixed \(index)\t日本語のテキスト\tabc 漢字 ", count: 10)
        default:
            "\(index)\ttab\tseparated\tcolumns"
        }
    }

    private func median<T: Comparable>(_ values: [T]) -> T {
        values.sorted()[values.count / 2]
    }

    private func memoryFootprint() -> Int {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &information) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return Int(information.phys_footprint)
    }
}

#if DEBUG
private let isReleaseBuild = false
#else
private let isReleaseBuild = true
#endif
