import AppKit
import CoreText

extension TerminalContentView {
    static func drawsSeparator(_ character: String, in rect: CGRect, context: CGContext) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
            (0xE0B0 ... 0xE0B3).contains(scalar.value)
        else {
            return false
        }
        let (edge, tip) = scalar.value < 0xE0B2 ? (rect.minX, rect.maxX) : (rect.maxX, rect.minX)
        context.saveGState()
        context.clip(to: rect)
        context.move(to: CGPoint(x: edge, y: rect.minY))
        context.addLine(to: CGPoint(x: tip, y: rect.midY))
        context.addLine(to: CGPoint(x: edge, y: rect.maxY))
        if scalar.value.isMultiple(of: 2) {
            context.fillPath()
        } else {
            context.strokePath()
        }
        context.restoreGState()
        return true
    }
}

final class GlyphCache {
    struct Run {
        let font: CTFont
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
    }

    struct Entry {
        let runs: [Run]
    }

    private struct Key: Hashable {
        let scalars: [Unicode.Scalar]
        let font: Int
        let isMirrored: Bool
    }

    private static let capacity = 8_192

    private var entries: [Key: Entry] = [:]
    private var asciiEntries = [Entry?](repeating: nil, count: 4 * 128)

    func entry(for character: String, font: NSFont, index: Int, isMirrored: Bool) -> Entry {
        if character.utf8.count == 1, let ascii = character.utf8.first, !isMirrored {
            if let entry = asciiEntries[index * 128 + Int(ascii)] {
                return entry
            }
            let entry = makeEntry(for: character, font: font, isMirrored: false)
            asciiEntries[index * 128 + Int(ascii)] = entry
            return entry
        }
        let key = Key(scalars: Array(character.unicodeScalars), font: index, isMirrored: isMirrored)
        if let entry = entries[key] {
            return entry
        }
        if entries.count >= Self.capacity {
            entries.removeAll()
        }
        let entry = makeEntry(for: character, font: font, isMirrored: isMirrored)
        entries[key] = entry
        return entry
    }

    private func makeEntry(for character: String, font: NSFont, isMirrored: Bool) -> Entry {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = isMirrored ? .rightToLeft : .natural
        let string = NSAttributedString(string: character, attributes: [.font: font, .paragraphStyle: style])
        let line = CTLineCreateWithAttributedString(string)
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun] ?? [])
            .map { run in
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
                let runFont = attributes?[.font] as? NSFont ?? font
                return Run(font: runFont, glyphs: glyphs, positions: positions)
            }
        return Entry(runs: runs)
    }
}
