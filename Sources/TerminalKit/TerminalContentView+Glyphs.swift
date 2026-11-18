import AppKit
import CoreText

extension TerminalContentView {
    static func drawsPowerlineSymbol(_ character: String, in rect: CGRect, font: NSFont, context: CGContext) -> Bool {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value,
            (0xE0A0 ... 0xE0A3).contains(value) || (0xE0B0 ... 0xE0B3).contains(value)
        else {
            return false
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 7, y: rect.minY + rect.height * y / 15)
        }
        func size(_ width: CGFloat, _ height: CGFloat) -> CGSize {
            CGSize(width: rect.width * width / 7, height: rect.width * height / 7)
        }
        context.saveGState()
        context.clip(to: rect)
        if value < 0xE0B0 {
            context.setLineWidth(rect.width / 6)
        }
        switch value {
        case 0xE0A0:
            context.move(to: point(1.75, 0))
            context.addLine(to: point(1.75, 15))
            context.move(to: point(4.7, 4))
            context.addLine(to: point(4.7, 9))
            context.addQuadCurve(to: point(1.75, 11.5), control: point(4.7, 11.5))
            context.strokePath()
            context.fillEllipse(in: CGRect(origin: point(3.7, 3.05), size: size(3, 3)))
        case 0xE0A2:
            let shackle = CGRect(origin: point(2.35, 4.2), size: size(2.85, 4))
            let radius = shackle.width / 2
            context.addPath(CGPath(roundedRect: shackle, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
            let body = CGRect(origin: point(0.95, 6.7), size: size(5.8, 4.9))
            let corner = rect.width / 7
            context.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        case 0xE0A1, 0xE0A3:
            let small =
                CTFontCreateCopyWithSymbolicTraits(font, font.pointSize / 2, nil, .traitBold, .traitBold) ?? font
            var glyphs: [CGGlyph] = [0, 0]
            CTFontGetGlyphsForCharacters(small, Array((value == 0xE0A1 ? "LN" : "CN").utf16), &glyphs, 2)
            let x = point(3.75, 0).x - CTFontGetAdvancesForGlyphs(small, .horizontal, glyphs, nil, 1) / 2
            let positions = [CGPoint(x: x, y: -point(0, 7.25).y), CGPoint(x: x, y: -point(0, 12).y)]
            CTFontDrawGlyphs(small, glyphs, positions, 2, context)
        default:
            let (edge, tip) = value < 0xE0B2 ? (rect.minX, rect.maxX) : (rect.maxX, rect.minX)
            context.move(to: CGPoint(x: edge, y: rect.minY))
            context.addLine(to: CGPoint(x: tip, y: rect.midY))
            context.addLine(to: CGPoint(x: edge, y: rect.maxY))
            if value.isMultiple(of: 2) {
                context.fillPath()
            } else {
                context.strokePath()
            }
        }
        context.restoreGState()
        return true
    }

    private static let blockElements: [UInt32: (quadrants: Int, alpha: CGFloat)] = [
        0x2580: (0b0011, 1), 0x2584: (0b1100, 1), 0x2588: (0b1111, 1), 0x258C: (0b0101, 1), 0x2590: (0b1010, 1),
        0x2591: (0b1111, 0.25), 0x2592: (0b1111, 0.5), 0x2593: (0b1111, 0.75), 0x2596: (0b0100, 1),
        0x2597: (0b1000, 1), 0x2598: (0b0001, 1), 0x2599: (0b1101, 1), 0x259A: (0b1001, 1), 0x259B: (0b0111, 1),
        0x259C: (0b1011, 1), 0x259D: (0b0010, 1), 0x259E: (0b0110, 1), 0x259F: (0b1110, 1),
    ]

    func drawsBlockElement(_ character: String, in cell: CGRect, context: CGContext) -> Bool {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value,
            let (quadrants, alpha) = Self.blockElements[value]
        else {
            return false
        }
        let rects = (0 ..< 4).filter { quadrants >> $0 & 1 == 1 }
            .map { quadrant in
                backingAlignedRect(
                    CGRect(
                        x: quadrant.isMultiple(of: 2) ? cell.minX : cell.midX,
                        y: quadrant < 2 ? cell.minY : cell.midY,
                        width: cell.width / 2,
                        height: cell.height / 2
                    ),
                    options: .alignAllEdgesNearest
                )
            }
        context.saveGState()
        context.setAlpha(alpha)
        context.fill(rects)
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
