import SwiftUI
import AnalyzersKit
import UIComponents

/// One row of the history: what happened in words, what the guard did about
/// it, and when. A repeat shows its time span and its count in the title.
struct GuardRowView: View {
    let row: GuardHistory.Row
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Tokens.Space.xl) {
                GlyphTile(glyph: row.glyph, side: 28)
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    Text(row.title)
                        .font(Tokens.Typography.rowTitleKey)
                    Text(row.outcome)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.xl)
                Text(row.timeText)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Tokens.Space.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this event")
    }
}

extension GuardHistory.Row {

    /// The tile at the row's edge: what kind of thing it is, tinted by how
    /// much it matters.
    var glyph: ActivityRow.Glyph {
        switch kind {
        case .stopped:
            ActivityRow.Glyph(symbol: "stop.circle.fill", tone: Tokens.Status.destructive, spins: false)
        case .crisisReport:
            ActivityRow.Glyph(symbol: "stethoscope", tone: Tokens.Status.destructive, spins: false, loud: true)
        case .pressure:
            ActivityRow.Glyph(symbol: "gauge.with.needle", tone: lead.pressureLevel.map { $0 >= 4 } == true
                              ? Tokens.Status.destructive : Tokens.Status.caution, spins: false)
        case .spike, .overLimit:
            ActivityRow.Glyph(symbol: "arrow.up.right", tone: Tokens.Status.caution, spins: false)
        case .cpu:
            ActivityRow.Glyph(symbol: "cpu", tone: Tokens.Status.preview, spins: false)
        }
    }
}
