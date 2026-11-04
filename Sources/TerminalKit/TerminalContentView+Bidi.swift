import AppKit
import CoreText
import TerminalCore

extension TerminalContentView {
    struct VisualOrder {
        var columns: [Int]
        var isReversed: [Bool]

        func logicalColumn(at x: CGFloat, in line: Terminal.Line) -> Int? {
            guard x >= 0, x < CGFloat(line.count), var column = columns.firstIndex(of: Int(x)) else {
                return nil
            }
            if line[column].width == 0, column > 0 {
                column -= 1
            }
            let width = max(Int(line[column].width), 1)
            let isAfter = x >= CGFloat(columns[column]) + CGFloat(width) / 2
            return isAfter != isReversed[column] ? column + width : column
        }
    }

    private static let leftToRight = {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .leftToRight
        return style
    }()

    static func visualOrder(of line: Terminal.Line, graphemes: Terminal.Graphemes) -> VisualOrder? {
        guard
            line.contains(where: {
                !$0.isASCII && graphemes.character(of: $0).unicodeScalars.contains(where: isRightToLeft)
            })
        else {
            return nil
        }
        var text = ""
        var length = 0
        var units: [(offset: Int, columns: Range<Int>)] = []
        for column in line.indices {
            if line[column].width == 0, let last = units.last {
                units[units.count - 1].columns = last.columns.lowerBound ..< column + 1
                continue
            }
            let character = graphemes.character(of: line[column])
            units.append((length, column ..< column + 1))
            text.append(character)
            length += character.utf16.count
        }
        let ctLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.paragraphStyle: leftToRight]))
        var order = VisualOrder(columns: Array(line.indices), isReversed: Array(repeating: false, count: line.count))
        var visual = 0
        for run in CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? [] {
            let range = CTRunGetStringRange(run)
            let isReversed = CTRunGetStatus(run).contains(.rightToLeft)
            var runUnits = units.filter { range.location ..< range.location + range.length ~= $0.offset }
            if isReversed {
                runUnits.reverse()
            }
            for unit in runUnits {
                for column in unit.columns {
                    order.columns[column] = visual + column - unit.columns.lowerBound
                    order.isReversed[column] = isReversed
                }
                visual += unit.columns.count
            }
        }
        return order
    }

    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590 ... 0x08FF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF, 0x1_0800 ... 0x1_0FFF, 0x1_E800 ... 0x1_EFFF:
            return true
        default:
            return false
        }
    }

    func visualOrder(ofRow row: Int) -> VisualOrder? {
        Self.visualOrder(of: line(at: row), graphemes: session.terminal.graphemes)
    }

    func rects(row: Int, columns: Range<Int>, order: VisualOrder?) -> [CGRect] {
        guard let order else {
            return [rect(row: row, columns: columns)]
        }
        var ranges: [Range<Int>] = []
        for column in columns.map({ order.columns.indices.contains($0) ? order.columns[$0] : $0 }).sorted() {
            if let last = ranges.last, last.upperBound == column {
                ranges[ranges.count - 1] = last.lowerBound ..< column + 1
            } else {
                ranges.append(column ..< column + 1)
            }
        }
        return ranges.map { rect(row: row, columns: $0) }
    }
}
