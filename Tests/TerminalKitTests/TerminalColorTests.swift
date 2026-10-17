import AppKit
import TerminalCore
import Testing

@testable import TerminalKit

struct TerminalColorTests {
    @Test func usesTheDefaultColorsOfTheView() {
        #expect(NSColor.terminal(.default, ansiColors: ansiColors) == nil)
    }

    @Test func usesTheStandardColorsOfTerminal() {
        #expect(components(.indexed(0)) == [0, 0, 0])
        #expect(components(.indexed(1)) == [194, 54, 33])
        #expect(components(.indexed(15)) == [233, 235, 235])
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
