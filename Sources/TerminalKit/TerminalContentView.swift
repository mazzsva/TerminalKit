import AppKit

final class TerminalContentView: NSView {
    private static let padding: CGFloat = 4

    let session: TerminalSession
    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    var cellSize: CGSize {
        CGSize(
            width: ("M" as NSString).size(withAttributes: [.font: font]).width,
            height: ceil(font.ascender - font.descender + font.leading)
        )
    }

    init(session: TerminalSession) {
        self.session = session
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        for (row, line) in session.terminal.screen.enumerated() {
            let text = String(line.map(\.character))
            let origin = CGPoint(x: Self.padding, y: Self.padding + CGFloat(row) * cellSize.height)
            NSAttributedString(string: text, attributes: attributes).draw(at: origin)
        }
    }
}
