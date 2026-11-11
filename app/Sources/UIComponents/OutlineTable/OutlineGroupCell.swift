import SwiftUI

/// The name cell of a group row: icon, name, then "9 folders · 96 KB" in secondary.
public struct OutlineGroupCell: View {
    let name: String
    let summary: String?
    let icon: Image?

    public init(name: String, summary: String? = nil, icon: Image? = nil) {
        self.name = name
        self.summary = summary
        self.icon = icon
    }

    public var body: some View {
        HStack {
            if let icon { icon }
            Text(name)
            if let summary {
                Text(summary).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
