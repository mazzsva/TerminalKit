import TerminalCore

extension TerminalContentView {
    struct JoinedCells {
        var heads: [Int: (text: String, end: Int)] = [:]
        var headsOfFollowers: [Int: Int] = [:]

        func expanded(_ columns: Range<Int>) -> Range<Int> {
            heads.reduce(columns) { range, shape in
                let (head, end) = (shape.key, shape.value.end)
                return head < range.upperBound && range.lowerBound < end
                    ? min(head, range.lowerBound) ..< max(end, range.upperBound) : range
            }
        }
    }

    private static let maximumJoinedBytes = 256

    static func joinedCells(
        in line: Terminal.Line,
        graphemes: Terminal.Graphemes,
        order: VisualOrder?
    ) -> JoinedCells? {
        guard line.contains(where: { !$0.isASCII }) else {
            return nil
        }
        var joined = JoinedCells()
        var column = 0
        while column < line.count {
            let width = max(Int(line[column].width), 1)
            var next = column + width
            if line[column].isText, !line[column].isSpace {
                var text = graphemes.character(of: line[column])
                var followers: [Int] = []
                while next < line.count, !line[next].isASCII, line[next].width > 0,
                    text.utf8.count < maximumJoinedBytes,
                    hasTheSamePaint(line[next].style, line[column].style),
                    isInVisualOrder(next, after: column, width: next - column, order)
                {
                    let following = graphemes.character(of: line[next])
                    guard joins(text, width: width, following, width: Int(line[next].width)) else {
                        break
                    }
                    text += following
                    followers.append(next)
                    next += Int(line[next].width)
                }
                if !followers.isEmpty {
                    joined.heads[column] = (text, next)
                    for follower in followers {
                        joined.headsOfFollowers[follower] = column
                    }
                }
            }
            column = next
        }
        return joined.heads.isEmpty ? nil : joined
    }

    private static func hasTheSamePaint(_ style: Terminal.Style, _ other: Terminal.Style) -> Bool {
        style.isInverse == other.isInverse && style.isHidden == other.isHidden
            && (style.isInverse ? style.foreground == other.foreground : style.background == other.background)
    }

    private static func isInVisualOrder(_ next: Int, after head: Int, width: Int, _ order: VisualOrder?) -> Bool {
        guard let order else {
            return true
        }
        return !order.isReversed[head] && !order.isReversed[next] && order.columns[next] == order.columns[head] + width
    }

    private static func joins(_ text: String, width: Int, _ next: String, width nextWidth: Int) -> Bool {
        guard let first = text.unicodeScalars.first else {
            return false
        }
        return !first.isASCII && width == 1 && nextWidth == 1 && (text + next).count == 1
    }
}
