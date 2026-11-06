import SwiftUI

public struct TerminalPalette: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var cursor: Color
    public var selection: Color
    public var ansiColors: [Color]
    private var customBold: Color?

    public var bold: Color {
        get { customBold ?? foreground }
        set { customBold = newValue }
    }

    public init(
        foreground: Color,
        background: Color,
        cursor: Color,
        selection: Color,
        ansiColors: [Color],
        bold: Color? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.ansiColors = ansiColors
        customBold = bold
    }

    public static let standard = TerminalPalette(
        foreground: color(0xE6CE, 0xE6CE, 0xE6CE),
        background: color(0x213D, 0x2743, 0x33E7).opacity(0.95),
        cursor: color(0x9D2C, 0x9D2C, 0x9D2C),
        selection: color(0x3370, 0x4E03, 0x5EBA),
        ansiColors: [
            color(0x354E, 0x4245, 0x4BCF), color(0xB480, 0x55F1, 0x47F9), color(0x6C95, 0xAAD2, 0x7107),
            color(0xC4C4, 0xACAC, 0x6262), color(0x6D6D, 0x9696, 0xB4B4), color(0xBDBD, 0x7B7B, 0xCDCD),
            color(0x7C16, 0xCB85, 0xCE42), color(0xDE68, 0xE648, 0xEC13), color(0x46BD, 0x5CD3, 0x6D12),
            color(0xE049, 0x6C9A, 0x5A49), color(0x7965, 0xBE4A, 0x7E0D), color(0xE5E5, 0xC8C8, 0x7272),
            color(0x6767, 0xB5B5, 0xEDED), color(0xD3D3, 0x8989, 0xE5E5), color(0x848C, 0xDE23, 0xE13A),
            color(0xE64A, 0xEF7A, 0xF63D),
        ],
        bold: color(0xF165, 0xF165, 0xF165)
    )

    private static func color(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red / 65_535, green: green / 65_535, blue: blue / 65_535)
    }
}
