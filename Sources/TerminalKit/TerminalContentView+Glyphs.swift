import AppKit
import CoreText

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

    func entry(for character: String, font: NSFont, index: Int, isMirrored: Bool = false) -> Entry {
        if character.utf8.count == 1, let ascii = character.utf8.first, ascii < 128, !isMirrored {
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
        let isMark = character.unicodeScalars.first?.properties.generalCategory == .spacingMark
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = isMirrored ? .rightToLeft : .natural
        let string = NSAttributedString(
            string: (isMark ? "\u{A0}" : "") + character, attributes: [.font: font, .paragraphStyle: style])
        let line = CTLineCreateWithAttributedString(string)
        let offset = isMark ? CTLineGetImageBounds(line, nil).minX : 0
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun] ?? [])
            .map { run in
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
                let runFont = attributes?[.font] as? NSFont ?? font
                return Run(
                    font: runFont, glyphs: glyphs, positions: positions.map { CGPoint(x: $0.x - offset, y: $0.y) })
            }
        return Entry(runs: runs)
    }
}
