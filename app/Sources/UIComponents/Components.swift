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

/// General-pane-style header: large tile, title, one-line description —
/// opens every settings pane so they all share the same anatomy.
public struct PaneHeader: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String

    public init(symbol: String, color: Color, title: String, caption: String) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.caption = caption
    }

    public var body: some View {
        VStack(spacing: 6) {
            IconTile(symbol: symbol, color: color, side: 34)
            Text(title).font(.title3.weight(.semibold))
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.horizontal, 24)
    }
}
