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
        let character: Character
        let font: Int
    }

    private static let capacity = 8_192

    private var entries: [Key: Entry] = [:]
    private var asciiEntries = [Entry?](repeating: nil, count: 4 * 128)

    func entry(for character: Character, font: NSFont, index: Int) -> Entry {
        if let ascii = character.asciiValue {
            if let entry = asciiEntries[index * 128 + Int(ascii)] {
                return entry
            }
            let entry = makeEntry(for: character, font: font)
            asciiEntries[index * 128 + Int(ascii)] = entry
            return entry
        }
        let key = Key(character: character, font: index)
        if let entry = entries[key] {
            return entry
        }
        if entries.count >= Self.capacity {
            entries.removeAll()
        }
        let entry = makeEntry(for: character, font: font)
        entries[key] = entry
        return entry
    }

    private func makeEntry(for character: Character, font: NSFont) -> Entry {
        let isMark = character.unicodeScalars.first?.properties.generalCategory == .spacingMark
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: (isMark ? "\u{A0}" : "") + String(character), attributes: [.font: font]))
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
