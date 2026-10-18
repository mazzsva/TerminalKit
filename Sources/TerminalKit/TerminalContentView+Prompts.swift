import AppKit

extension TerminalContentView {
    func scrollToPrompt(isPrevious: Bool) {
        let terminal = session.terminal
        guard !terminal.isAlternateScreenActive, let visibleRect = enclosingScrollView?.documentVisibleRect else {
            return
        }
        let rows = terminal.commands.compactMap { $0.prompt.map { $0.row - terminal.removedScrollbackCount } }
        let topRow = Int((visibleRect.minY / cellSize.height).rounded())
        if let row = isPrevious ? rows.last(where: { $0 < topRow }) : rows.first(where: { $0 > topRow }) {
            scroll(CGPoint(x: 0, y: CGFloat(row) * cellSize.height))
        } else if !isPrevious {
            scrollToBottom()
        }
    }
}
