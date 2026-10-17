import AppKit

final class TerminalContentView: NSView {
    private static let padding: CGFloat = 4

    let session: TerminalSession
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let cellSize: CGSize

    init(session: TerminalSession) {
        self.session = session
        cellSize = CGSize(
            width: ("M" as NSString).size(withAttributes: [.font: font]).width,
            height: ceil(font.ascender - font.descender + font.leading)
        )
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard let input = event.terminalInput else {
            super.keyDown(with: event)
            return
        }
        session.send(input)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        session.resize(
            columns: max(Int((newSize.width - 2 * Self.padding) / cellSize.width), 1),
            rows: max(Int((newSize.height - 2 * Self.padding) / cellSize.height), 1)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        for (row, line) in session.terminal.screen.enumerated() {
            let text = String(line.map(\.character))
            NSAttributedString(string: text, attributes: attributes).draw(at: rect(row: row, column: 0).origin)
        }

        let cursor = session.terminal.cursor
        NSColor.textColor.withAlphaComponent(0.5).setFill()
        rect(row: cursor.row, column: cursor.column).fill(using: .sourceOver)
    }

    private func rect(row: Int, column: Int) -> CGRect {
        CGRect(
            x: Self.padding + CGFloat(column) * cellSize.width,
            y: Self.padding + CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
    }
}
