import AppKit
import Testing

@testable import TerminalKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TerminalFindTests {
    @Test func findsTextAcrossAWrappedRow() async throws {
        let scrollView = try await findView(running: "printf 'see https://example.com/x end'", columns: 10)
        let view = scrollView.terminalView
        let range = (view.string as NSString).range(of: "https://example.com/x")
        #expect(range.location == 4)
        let rects = try #require(view.rects(forCharacterRange: range)).map(\.rectValue)
        #expect(
            rects == [
                view.rect(row: 0, columns: 4 ..< 10), view.rect(row: 1, columns: 0 ..< 10),
                view.rect(row: 2, columns: 0 ..< 5),
            ])
    }

    @Test func mapsWideAndCombinedCharacters() async throws {
        let scrollView = try await findView(running: "printf 'a中e\\314\\201🙂x'")
        let view = scrollView.terminalView
        let range = (view.string as NSString).range(of: "x")
        #expect(range.location == 6)
        #expect(view.rects(forCharacterRange: range)?.map(\.rectValue) == [view.rect(row: 0, columns: 6 ..< 7)])
        let wide = (view.string as NSString).range(of: "中")
        #expect(view.rects(forCharacterRange: wide)?.map(\.rectValue) == [view.rect(row: 0, columns: 1 ..< 3)])
        let emoji = (view.string as NSString).range(of: "🙂")
        #expect(view.rects(forCharacterRange: emoji)?.map(\.rectValue) == [view.rect(row: 0, columns: 4 ..< 6)])
    }

    @Test func mapsAnEmojiSequence() async throws {
        let scrollView = try await findView(running: "printf 'a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}x'")
        let view = scrollView.terminalView
        let emoji = (view.string as NSString).range(of: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
        #expect(view.rects(forCharacterRange: emoji)?.map(\.rectValue) == [view.rect(row: 0, columns: 1 ..< 3)])
        let range = (view.string as NSString).range(of: "x")
        #expect(view.rects(forCharacterRange: range)?.map(\.rectValue) == [view.rect(row: 0, columns: 3 ..< 4)])
    }

    @Test func selectsTheFoundText() async throws {
        let scrollView = try await findView(running: "printf 'one two\\r\\nthree'")
        let view = scrollView.terminalView
        view.selectedRanges = [NSValue(range: (view.string as NSString).range(of: "two\nth"))]
        #expect(view.selectedText == "two\nth")
        #expect(view.firstSelectedRange == (view.string as NSString).range(of: "two\nth"))
        view.selectedRanges = [NSValue(range: NSRange(location: 2, length: 0))]
        #expect(view.selection == nil)
    }

    @Test func ignoresRangesOutsideTheText() async throws {
        let scrollView = try await findView(running: "printf 'short'")
        let view = scrollView.terminalView
        let range = NSRange(location: view.string.utf16.count - 1, length: 10)
        #expect(view.rects(forCharacterRange: range)?.isEmpty == true)
        view.selectedRanges = [NSValue(range: range)]
        #expect(view.selection == nil)
        #expect(view.rects(forCharacterRange: NSRange(location: NSNotFound, length: 0))?.isEmpty == true)
    }

    @Test func givesTheWholeTextToTheFinder() async throws {
        let scrollView = try await findView(running: "seq 1 50")
        let view = scrollView.terminalView
        var range = NSRange()
        #expect(view.contentView(at: 7, effectiveCharacterRange: &range) === view)
        #expect(range == NSRange(location: 0, length: view.string.utf16.count))
        #expect(view.string.hasPrefix("1\n2\n3\n"))
        let visible = view.visibleCharacterRanges.map(\.rangeValue)
        #expect(visible == [view.accessibilityVisibleCharacterRange()])
    }

    @Test func scrollsTheMatchIntoView() async throws {
        let scrollView = try await findView(running: "seq 1 100")
        let view = scrollView.terminalView
        view.scrollRangeToVisible((view.string as NSString).range(of: "\n5\n"))
        let top = Int((scrollView.contentView.bounds.minY / view.cellSize.height).rounded())
        #expect((0 ... 5).contains(top))
    }

    @Test func findsTextAfterTheScrollbackIsErased() async throws {
        let scrollView = try await findView(running: "seq 1 11500; printf '\\033[3J'")
        let view = scrollView.terminalView
        #expect(view.session.terminal.removedScrollbackCount > 0)
        let range = (view.string as NSString).range(of: "\n11499\n")
        #expect(range.location != NSNotFound)
        view.selectedRanges = [NSValue(range: NSRange(location: range.location + 1, length: 5))]
        #expect(view.selectedText == "11499")
    }

    @Test func findsTextOnTheAlternateScreen() async throws {
        let scrollView = try await findView(running: "echo before; printf '\\033[?1049hon the alternate screen'")
        let view = scrollView.terminalView
        let range = (view.string as NSString).range(of: "alternate")
        #expect(range.location != NSNotFound)
        view.selectedRanges = [NSValue(range: range)]
        #expect(view.selectedText == "alternate")
    }

    @Test func findsNoTextAcrossTheAlternateScreen() async throws {
        let scrollView = try await findView(
            running:
                "r=$(stty size | cut -d' ' -f1); printf abcdefghijKLMNOP; "
                + "i=1; while [ $i -lt $r ]; do printf '\\n'; i=$((i+1)); done; printf '\\033[?1049h\\033[Hvim'",
            columns: 10
        )
        let view = scrollView.terminalView
        #expect((view.string as NSString).range(of: "jvim").location == NSNotFound)
        #expect((view.string as NSString).range(of: "abcdefghijKLMNOP\n").location == 0)
    }

    @Test func findsTheNormalScreenOnTheAlternateScreen() async throws {
        let scrollView = try await findView(running: "echo before; printf '\\033[?1049h\\033[Hvim'")
        let view = scrollView.terminalView
        let range = (view.string as NSString).range(of: "before")
        #expect(range.location != NSNotFound)
        view.selectedRanges = [NSValue(range: range)]
        #expect(view.selectedText == "before")
    }

    @Test(arguments: [true, false])
    func readsASelectionOfTheAlternateScreenAfterTheExit(selectsAll: Bool) throws {
        let session = TerminalSession(running: "true")
        let scrollView = TerminalScrollView(session: session)
        scrollView.scrollerStyle = .overlay
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let view = scrollView.terminalView
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(view)
        scrollView.layoutSubtreeIfNeeded()
        let normal = "normal text http://example.com/a"
        _ = session.liveTerminal.receive(
            Array((normal + "\r\n\u{1B}[?1049h\u{1B}[Halt one\r\nalt two\r\nhttp://example.com/b").utf8))
        scrollView.layoutSubtreeIfNeeded()
        let rows = session.terminal.rows
        if selectsAll {
            view.selectAll(nil)
        } else {
            view.mouseDown(with: try mouseEvent(.leftMouseDown, row: rows, column: 0, in: view))
            view.mouseDragged(with: try mouseEvent(.leftMouseDragged, row: rows + 2, column: 20, in: view))
            view.mouseUp(with: try mouseEvent(.leftMouseUp, row: rows + 2, column: 20, in: view))
        }
        #expect(view.selectedText?.hasSuffix("alt one\nalt two\nhttp://example.com/b") == true)
        let stale = view.selection

        _ = session.liveTerminal.receive(Array("\u{1B}[?1049l".utf8))
        scrollView.layoutSubtreeIfNeeded()
        draw(view)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TerminalFindTests-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        view.copySelection(to: pasteboard)
        let kept = normal + String(repeating: "\n", count: rows - 1)
        let length = (view.string as NSString).length
        #expect(pasteboard.string(forType: .string) == (selectsAll ? kept : nil))
        #expect(view.accessibilitySelectedText() == (selectsAll ? kept : ""))
        let range = selectsAll ? NSRange(location: 0, length: length) : NSRange(location: length, length: 0)
        #expect(view.accessibilitySelectedTextRange() == range)
        #expect(view.selectedRanges == [NSValue(range: range)])

        scrollView.textFinder.performAction(.showFindInterface)
        let field = try #require(scrollView.findBarView.flatMap { searchField(in: $0) })
        window.makeFirstResponder(field)
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.insertText("normal", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.selection = stale
        #expect(sendFindPanelAction(.next, in: window))
        #expect(view.firstSelectedRange == NSRange(location: 0, length: 6))

        view.selection = stale
        view.mouseDown(with: try mouseEvent(.leftMouseDown, row: 0, column: 3, in: view, modifierFlags: .shift))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, row: 0, column: 3, in: view, modifierFlags: .shift))
        #expect(view.selectedText == String(kept.dropFirst(3)))

        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: rows + 2, column: 5, in: view, modifierFlags: .command))
        #expect(view.hoveredLink == nil)
        view.mouseMoved(with: try mouseEvent(.mouseMoved, row: 0, column: 15, in: view, modifierFlags: .command))
        #expect(view.hoveredLink?.url == URL(string: "http://example.com/a"))
        draw(view)
    }

    @Test func drawsTheFoundCharacters() async throws {
        let scrollView = try await findView(running: "printf '\\033[31ma\\033[0m c\\033[4mb\\033[0md\\033[31me'")
        let view = scrollView.terminalView
        let rect = view.rect(row: 0, columns: 3 ..< 4)
        let image = NSImage(size: view.bounds.size, flipped: true) { _ in
            NSColor.yellow.setFill()
            view.bounds.fill()
            view.drawCharacters(in: NSRange(location: 3, length: 1), forContentView: view)
            return true
        }
        let representation = try #require(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init(cgImage:))
        )
        let scale = CGFloat(representation.pixelsWide) / view.bounds.width
        let pixels = { (rect: CGRect) in
            stride(from: Int(rect.minY * scale), to: Int(rect.maxY * scale), by: 1)
                .flatMap { y in
                    stride(from: Int(rect.minX * scale), to: Int(rect.maxX * scale), by: 1)
                        .compactMap { representation.colorAt(x: $0, y: y)?.usingColorSpace(.sRGB)?.redComponent }
                }
        }
        #expect(pixels(rect).contains { $0 < 0.5 })
        let font = view.fonts.regular
        let y = rect.minY + font.ascender - font.underlinePosition + max(font.underlineThickness, 1) / 2
        #expect(pixels(CGRect(x: rect.minX, y: y, width: rect.width, height: 1 / scale)).allSatisfy { $0 < 0.5 })
        #expect(pixels(view.rect(row: 0, columns: 0 ..< 3)).allSatisfy { $0 > 0.5 })
        #expect(pixels(view.rect(row: 0, columns: 4 ..< 6)).allSatisfy { $0 > 0.5 })
    }

    @Test func drawsTheFoundRightToLeftCharacterInItsVisualCell() async throws {
        let word = try await findView(running: "printf '\\327\\220\\327\\221'")
        let reference = try await findView(running: "printf ' \\327\\220'")
        let images = try [(word.terminalView, 0), (reference.terminalView, 1)]
            .map { view, location in
                let image = NSImage(size: view.bounds.size, flipped: true) { _ in
                    NSColor.white.setFill()
                    view.bounds.fill()
                    view.drawCharacters(in: NSRange(location: location, length: 1), forContentView: view)
                    return true
                }
                return try #require(
                    image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(NSBitmapImageRep.init(cgImage:))
                )
            }
        let view = word.terminalView
        let scale = CGFloat(images[0].pixelsWide) / view.bounds.width
        func ink(_ columns: Range<Int>, in image: NSBitmapImageRep) -> [CGFloat] {
            let rect = view.rect(row: 0, columns: columns)
            return stride(from: Int(rect.minY * scale), to: Int(rect.maxY * scale), by: 1)
                .flatMap { y in
                    stride(from: Int(rect.minX * scale), to: Int(rect.maxX * scale), by: 1)
                        .compactMap { image.colorAt(x: $0, y: y)?.usingColorSpace(.sRGB)?.redComponent }
                }
        }
        #expect(ink(0 ..< 1, in: images[0]).allSatisfy { $0 > 0.5 })
        #expect(ink(1 ..< 2, in: images[0]).contains { $0 < 0.5 })
        #expect(zip(ink(1 ..< 2, in: images[0]), ink(1 ..< 2, in: images[1])).allSatisfy { abs($0 - $1) < 0.2 })
    }

    @Test func tellsTheFinderWhenTheTextChanges() async throws {
        let session = TerminalSession(running: "printf a; read line; printf b")
        let scrollView = TerminalScrollView(session: session)
        scrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        scrollView.layoutSubtreeIfNeeded()
        let finder = FinderSpy()
        scrollView.textFinder = finder
        try session.start()
        await session.waitForText("a")
        draw(scrollView.terminalView)
        let changes = finder.changes
        draw(scrollView.terminalView)
        #expect(finder.changes == changes)
        session.send("\r")
        await session.waitForExit()
        draw(scrollView.terminalView)
        #expect(finder.changes > changes)
    }

    @Test func showsTheFindBarForTheFindMenu() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(scrollView.terminalView)
        #expect(sendFindPanelAction(.showFindPanel, in: window))
        #expect(scrollView.isFindBarVisible)
        let field = try #require(scrollView.findBarView.flatMap { searchField(in: $0) })
        window.makeFirstResponder(field)
        #expect(window.firstResponder !== scrollView.terminalView)
        window.firstResponder?.keyDown(with: try keyDown("\u{1B}"))
        #expect(!scrollView.isFindBarVisible)
        #expect(window.firstResponder === scrollView.terminalView)
    }

    @Test func performsTheFindMenuAction() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(scrollView.terminalView)
        let item = NSMenuItem(
            title: "Find", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "")
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        #expect(scrollView.terminalView.validateMenuItem(item))
        let replace = NSMenuItem(title: "Replace", action: item.action, keyEquivalent: "")
        replace.tag = NSTextFinder.Action.replace.rawValue
        #expect(!scrollView.terminalView.validateMenuItem(replace))
        scrollView.terminalView.performTextFinderAction(item)
        #expect(scrollView.isFindBarVisible)
        #expect(window.contentView === scrollView)
    }

    @Test func takesTheFindPanelActionFromTheTerminalAndTheFindBar() async throws {
        let scrollView = try await findView(running: "printf 'text one text two'")
        let view = scrollView.terminalView
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(view)
        let action = #selector(NSTextView.performFindPanelAction(_:))
        #expect(target(of: action, in: window) === scrollView)
        scrollView.textFinder.performAction(.showFindInterface)
        let field = try #require(scrollView.findBarView.flatMap { searchField(in: $0) })
        window.makeFirstResponder(field)
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(target(of: action, in: window) === scrollView)
        editor.insertText("text", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(scrollView.validateMenuItem(findPanelItem(.next)))
        #expect(scrollView.validateMenuItem(findPanelItem(.previous)))
        #expect(sendFindPanelAction(.next, in: window))
        #expect(view.firstSelectedRange == NSRange(location: 0, length: 4))
        #expect(sendFindPanelAction(.next, in: window))
        #expect(view.firstSelectedRange == NSRange(location: 9, length: 4))
        #expect(sendFindPanelAction(.previous, in: window))
        #expect(view.firstSelectedRange == NSRange(location: 0, length: 4))
    }

    @Test func validatesTheFindPanelAction() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let view = scrollView.terminalView
        #expect(scrollView.validateMenuItem(findPanelItem(.showFindPanel)))
        #expect(!scrollView.validateMenuItem(findPanelItem(.setFindString)))
        view.selectedRanges = [NSValue(range: (view.string as NSString).range(of: "text"))]
        #expect(scrollView.validateMenuItem(findPanelItem(.setFindString)))
        #expect(!scrollView.validateMenuItem(findPanelItem(.replace)))
        #expect(
            scrollView.validateMenuItem(
                NSMenuItem(title: "", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "")))
        let item = findPanelItem(.showFindPanel)
        item.tag = 0
        #expect(!scrollView.validateMenuItem(item))
    }

    @Test func performsTheFindPanelActionForEachTag() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let finder = FinderSpy()
        scrollView.textFinder = finder
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(scrollView.terminalView)
        for action in [NSFindPanelAction.showFindPanel, .next, .previous, .setFindString] {
            #expect(sendFindPanelAction(action, in: window))
        }
        #expect(finder.actions == [.showFindInterface, .nextMatch, .previousMatch, .setSearchString])
    }

    @Test func performsTheFindPanelActionForAButton() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(scrollView.terminalView)
        let button = NSButton()
        button.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        #expect(
            window.firstResponder?.tryToPerform(#selector(NSTextView.performFindPanelAction(_:)), with: button) == true)
        #expect(scrollView.isFindBarVisible)
    }

    @Test func leavesTheFindKeysToTheMenu() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let window = KeyWindow(contentView: scrollView)
        window.makeFirstResponder(scrollView.terminalView)
        let keys: [(String, NSEvent.ModifierFlags)] = [
            ("f", .command), ("g", .command), ("G", [.command, .shift]), ("e", .command),
        ]
        for (key, modifierFlags) in keys {
            #expect(!scrollView.performKeyEquivalent(with: try keyDown(key, modifierFlags: modifierFlags)))
        }
        #expect(!scrollView.isFindBarVisible)
    }

    @Test func givesTheFocusBackWhenTheFindBarHides() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let window = KeyWindow(contentView: scrollView)
        scrollView.isFindBarVisible = true
        let scroller = try #require(scrollView.verticalScroller)
        scroller.refusesFirstResponder = false
        #expect(window.makeFirstResponder(scroller))
        scrollView.isFindBarVisible = false
        #expect(window.firstResponder === scrollView.terminalView)
    }

    @Test func leavesTheFocusInOtherViewsWhenTheFindBarHides() async throws {
        let scrollView = try await findView(running: "printf 'text'")
        let container = NSView()
        let field = NSTextField()
        container.addSubview(scrollView)
        container.addSubview(field)
        let window = KeyWindow(contentView: container)
        scrollView.isFindBarVisible = true
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSText)
        scrollView.isFindBarVisible = false
        #expect(window.firstResponder === editor)
    }
}

private final class FinderSpy: NSTextFinder {
    var changes = 0
    var actions: [NSTextFinder.Action] = []

    override func noteClientStringWillChange() {
        changes += 1
    }

    override func performAction(_ op: NSTextFinder.Action) {
        actions.append(op)
    }
}

@MainActor
private func findPanelItem(_ action: NSFindPanelAction) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
    item.tag = Int(action.rawValue)
    return item
}

@MainActor
private func sendFindPanelAction(_ action: NSFindPanelAction, in window: NSWindow) -> Bool {
    window.firstResponder?.tryToPerform(#selector(NSTextView.performFindPanelAction(_:)), with: findPanelItem(action))
        == true
}

@MainActor
private func target(of action: Selector, in window: NSWindow) -> NSResponder? {
    window.firstResponder.flatMap { sequence(first: $0, next: \.nextResponder).first { $0.responds(to: action) } }
}

@MainActor
private func searchField(in view: NSView) -> NSSearchField? {
    view as? NSSearchField ?? view.subviews.lazy.compactMap(searchField).first
}

@MainActor
private func draw(_ view: NSView) {
    if let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: representation)
    }
}

@MainActor
private func findView(running script: String, columns: Int = 40) async throws -> TerminalScrollView {
    let session = TerminalSession(running: script)
    let scrollView = TerminalScrollView(session: session)
    scrollView.scrollerStyle = .overlay
    let view = scrollView.terminalView
    scrollView.frame = NSRect(
        x: 0,
        y: 0,
        width: 2 * TerminalContentView.padding + (CGFloat(columns) + 0.5) * view.cellSize.width,
        height: TerminalContentView.topPadding + TerminalContentView.bottomPadding + 10.5 * view.cellSize.height
    )
    scrollView.layoutSubtreeIfNeeded()
    try session.start()
    await session.waitForExit()
    scrollView.layoutSubtreeIfNeeded()
    return scrollView
}
