import SwiftUI

extension View {
    public func terminalFont(_ font: NSFont) -> some View {
        environment(\.terminalFont, font)
    }
}

extension EnvironmentValues {
    @Entry var terminalFont: NSFont?
}
