import AppKit
import TerminalCore
import Testing

@testable import TerminalKit

struct TerminalColorTests {
    @Test func usesTheDefaultColorsOfTheView() {
        #expect(NSColor.terminal(.default, ansiColors: ansiColors) == nil)
    }

    @Test func usesTheANSIColorsOfThePalette() {
        #expect(NSColor.terminal(.indexed(0), ansiColors: ansiColors) === ansiColors[0])
        #expect(NSColor.terminal(.indexed(15), ansiColors: ansiColors) === ansiColors[15])
    }

    @Test(arguments: [(NSAppearance.Name.aqua, CGFloat(0)), (.darkAqua, 1)])
    func showsTheStandardCursorInEachAppearance(appearance: NSAppearance.Name, white: CGFloat) throws {
        let cursor = NSColor(TerminalPalette.standard.cursor)
        try #require(NSAppearance(named: appearance))
            .performAsCurrentDrawingAppearance {
                #expect(cursor.usingColorSpace(.sRGB)?.redComponent == white)
            }
    }

    @Test func usesTheColorCube() {
        #expect(components(.indexed(16)) == [0, 0, 0])
        #expect(components(.indexed(17)) == [0, 0, 95])
        #expect(components(.indexed(52)) == [95, 0, 0])
        #expect(components(.indexed(231)) == [255, 255, 255])
    }

    @Test func usesTheGrayRamp() {
        #expect(components(.indexed(232)) == [8, 8, 8])
        #expect(components(.indexed(255)) == [238, 238, 238])
    }

    @Test func usesTrueColors() {
        #expect(components(.rgb(red: 1, green: 128, blue: 255)) == [1, 128, 255])
    }
}

private func components(_ color: Terminal.Color) -> [Int]? {
    guard let color = NSColor.terminal(color, ansiColors: ansiColors)?.usingColorSpace(.sRGB) else {
        return nil
    }
    return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
}

private let ansiColors = TerminalPalette.standard.ansiColors.map(NSColor.init)
