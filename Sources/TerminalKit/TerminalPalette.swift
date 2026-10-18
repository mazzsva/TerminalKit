import SwiftUI

public struct TerminalPalette: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    public var cursor: Color
    public var selection: Color
    public var ansiColors: [Color]

    public init(foreground: Color, background: Color, cursor: Color, selection: Color, ansiColors: [Color]) {
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.ansiColors = ansiColors
    }

    public static let standard = TerminalPalette(
        foreground: Color(nsColor: .textColor),
        background: Color(nsColor: .textBackgroundColor),
        cursor: Color(nsColor: .textColor).opacity(0.5),
        selection: Color(nsColor: .selectedTextBackgroundColor),
        ansiColors: [
            (0, 0, 0), (194, 54, 33), (37, 188, 36), (173, 173, 39),
            (73, 46, 225), (211, 56, 211), (51, 187, 200), (203, 204, 205),
            (129, 131, 131), (252, 57, 31), (49, 231, 34), (234, 236, 35),
            (88, 51, 255), (249, 53, 248), (20, 240, 240), (233, 235, 235),
        ]
        .map { Color(.sRGB, red: Double($0.0) / 255, green: Double($0.1) / 255, blue: Double($0.2) / 255) }
    )
}
