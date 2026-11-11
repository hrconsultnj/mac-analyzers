import SwiftUI
import AnalyzersKit
import UIComponents

/// One run in the history, in two lines: its name with its mode, and one plain
/// sentence saying what happened. Who started it and when sit on the trailing
/// side ("Schedule · 8 min ago"); a preview waiting for a decision carries a
/// Review button; a click anywhere else opens the run.
struct ActivityRowView: View {
    let row: ActivityRow
    let now: Date
    /// What a running job is doing right now; the row's own line is a snapshot.
    var liveLine: String?
    let onOpen: () -> Void
    let onReview: (() -> Void)?
    let onStop: (() -> Void)?

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Tokens.Space.xl) {
                GlyphTile(glyph: row.glyph, side: 28)
                VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                    Text(row.displayTitle)
                        .font(Tokens.Typography.rowTitleKey)
                        .lineLimit(1)
                    Text(liveLine ?? row.line)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(row.isFailed ? Tokens.Status.destructive.tint : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tokens.Space.xl)
                trailing
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
        .accessibilityHint("Opens this run")
    }

    @ViewBuilder private var trailing: some View {
        if row.status == .running, let started = row.started {
            Text(started, style: .timer)
                .font(Tokens.Typography.value)
                .foregroundStyle(.secondary)
        } else if row.status != .none {
            // a queued job has no start time and so, no starter either: say nothing
            Text(trailingText)
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .help("\(row.startedBy.map { "\($0). " } ?? "")\(row.exactTime)")
        }
        if let onReview {
            Button("Review", action: onReview)
                .controlSize(.small)
                .tint(Tokens.Status.caution.tint)
        }
        if let onStop {
            Button("Stop", action: onStop)
                .controlSize(.small)
        }
    }

    /// "Schedule · 8 min ago", or just the time when nothing says who started it.
    private var trailingText: String {
        [row.starterShort, row.timeText(now: now)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The small tile that carries a run's state. Quiet by design: a tinted
/// background with a coloured glyph, so a routine success recedes and the
/// orange of a waiting review and the red of a failure are what the eye lands on.
struct GlyphTile: View {
    let glyph: ActivityRow.Glyph
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.icon(side) + 2)
                .fill(glyph.tone.tint.opacity(glyph.loud ? 0.22 : 0.12))
            if glyph.spins {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: glyph.symbol)
                    .font(Tokens.Typography.tileGlyph(side))
                    .foregroundStyle(glyph.tone.tint)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
