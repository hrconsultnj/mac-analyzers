import SwiftUI

/// The name cell of a group row: icon, name, then "9 folders · 96 KB" in secondary.
///
/// The icon is drawn at `iconSize` points (16, the size of a row's own icons, unless the caller says
/// otherwise), whatever size the image has: a caller hands in the image as it is and never makes a
/// resized copy of it.
public struct OutlineGroupCell: View {
    let name: String
    let summary: String?
    let icon: Image?
    let iconSize: CGFloat

    public init(name: String, summary: String? = nil, icon: Image? = nil, iconSize: CGFloat = 16) {
        self.name = name
        self.summary = summary
        self.icon = icon
        self.iconSize = iconSize
    }

    public var body: some View {
        HStack {
            if let icon {
                // an icon is a picture of a fixed size, not a control
                icon.resizable().scaledToFit().frame(width: iconSize, height: iconSize)
            }
            Text(name)
            if let summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
