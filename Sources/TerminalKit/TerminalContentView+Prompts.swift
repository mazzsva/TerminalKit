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

    func scrollToCommand(_ id: Int) {
        let terminal = session.liveTerminal
        let index = id - terminal.removedCommandCount
        guard !terminal.isAlternateScreenActive, terminal.commands.indices.contains(index),
            let row = (terminal.commands[index].prompt ?? terminal.commands[index].output)?.row,
            row >= terminal.removedScrollbackCount
        else {
            return
        }
        scroll(CGPoint(x: 0, y: CGFloat(row - terminal.removedScrollbackCount) * cellSize.height))
    }
}
