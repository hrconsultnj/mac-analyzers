import SwiftUI

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
            IconTile(symbol: symbol, color: color, side: 44)
                .accessibilityHidden(true)  // decorative — title below already names the pane
            Text(title).font(.title2.weight(.bold))
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
