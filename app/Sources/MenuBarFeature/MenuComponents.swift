import SwiftUI
import AppKit
import AnalyzersKit
import UIComponents

/// A row that is one button: the whole row is the hit area, it reads as
/// pressable (the plain style darkens on press), and it fills the panel's
/// width whatever it holds — one layout for every state.
struct MenuRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A guard event as a named row: what happened to which app, in a sentence,
/// and when. Opens Memory Guard. Text wraps rather than truncating.
struct MenuEventRow: View {
    let row: OverviewModel.EventRow

    var body: some View {
        MenuRowButton(action: { SettingsOpener.open(target: "log:guardLog") }) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: row.event.symbol)
                    .foregroundStyle(row.event.tint)
                    .accessibilityHidden(true)  // decorative — the title already says what happened
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.callout)
                    Text(row.outcome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // is this spike or hog still going, or already over?
                if let live = row.event.isProcessStillRunning { LiveStateChip(active: live) }
                Text(row.when, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .help(row.event.raw)
    }
}
