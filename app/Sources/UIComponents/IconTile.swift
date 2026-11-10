import SwiftUI

/// System-Settings-style colored icon tile — the visual language of the
/// Settings sidebar, reused across the menu and the settings window.
public struct IconTile: View {
    let symbol: String
    let color: Color
    let side: CGFloat

    public init(symbol: String, color: Color, side: CGFloat = 16) {
        self.symbol = symbol
        self.color = color
        self.side = side
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: side * 0.24))
    }
}
