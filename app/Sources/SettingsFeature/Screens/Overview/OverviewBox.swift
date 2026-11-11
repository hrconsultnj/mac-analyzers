import SwiftUI

/// One summary on Overview: a native group box with an icon and a title, and rows inside.
struct OverviewBox<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) { content }
                // fills the height of its row, so boxes side by side end together
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
        } label: {
            Label(title, systemImage: symbol).font(.headline)
        }
    }
}

/// A row that is one button: the whole row is the hit area, a chevron says it
/// opens something, and it fills the box's width whatever it holds.
struct OverviewRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack {
                label
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)  // decorative — the row's text says where it goes
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A label with its value, as a row that opens the screen behind the number.
struct OverviewValueRow: View {
    let label: String
    let value: String
    let action: () -> Void
    var caption: String? = nil

    var body: some View {
        OverviewRow(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(label)
                    Spacer(minLength: 8)
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
