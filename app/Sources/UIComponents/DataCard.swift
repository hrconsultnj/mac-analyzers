import AppKit
import SwiftUI

/// Settings-pane-weight data row: leading icon (tile or real app icon),
/// title/subtitle, trailing value + liveness chip + badge — the "card"
/// anatomy from the Apple Storage Management reference.
public struct DataCard: View {
    let icon: AnyView
    let title: String
    let subtitle: String?
    let trailing: String?
    let badge: (text: String, color: Color)?
    let live: Bool?

    public init(symbol: String, color: Color, title: String,
                subtitle: String? = nil, trailing: String? = nil,
                badge: (text: String, color: Color)? = nil,
                live: Bool? = nil) {
        self.icon = AnyView(IconTile(symbol: symbol, color: color, side: 20))
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.badge = badge
        self.live = live
    }

    public init(appIcon: NSImage, title: String,
                subtitle: String? = nil, trailing: String? = nil,
                badge: (text: String, color: Color)? = nil,
                live: Bool? = nil) {
        self.icon = AnyView(Image(nsImage: appIcon).resizable().frame(width: 20, height: 20))
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.badge = badge
        self.live = live
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            icon
                .accessibilityHidden(true)  // decorative — title below already names the row
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let live {
                LiveStateChip(active: live)
            }
            if let badge {
                BadgeCapsule(text: badge.text, color: badge.color)
            }
        }
        .padding(.vertical, 3)
    }
}
