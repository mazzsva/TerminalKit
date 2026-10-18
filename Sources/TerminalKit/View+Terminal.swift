import SwiftUI

extension View {
    public func terminalFont(_ font: NSFont) -> some View {
        environment(\.terminalFont, font)
    }

    public func terminalPalette(_ palette: TerminalPalette) -> some View {
        environment(\.terminalPalette, palette)
    }
}

extension EnvironmentValues {
    @Entry var terminalFont: NSFont?
    @Entry var terminalPalette = TerminalPalette.standard
}
