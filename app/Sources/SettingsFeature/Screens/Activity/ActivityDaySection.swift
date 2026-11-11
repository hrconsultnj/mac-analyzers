import SwiftUI
import AnalyzersKit
import UIComponents

/// One day of history. The header names the day and says what it added up to
/// ("6 runs · freed 12.4 GB · 1 failed"); clicking it folds the day away.
///
/// A header button hides the rows rather than using `Section(isExpanded:)`,
/// which only collapses in the sidebar list style.
struct ActivityDaySection<RowContent: View>: View {
    let day: ActivityDay
    let filter: ActivityFilter
    let now: Date
    @ViewBuilder let row: (ActivityRow) -> RowContent

    var body: some View {
        let expanded = filter.isExpanded(day, now: now)
        Section {
            if expanded {
                ForEach(day.rows) { entry in row(entry) }
            }
        } header: {
            Button {
                withAnimation(.snappy(duration: 0.2)) { filter.toggle(day) }
            } label: {
                HStack(spacing: Tokens.Space.m) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: Tokens.Icon.inline)
                    Text(day.title(now: now))
                        .font(Tokens.Typography.sectionTitle)
                        .foregroundStyle(.primary)
                    Text(day.summary)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.title(now: now)), \(day.summary)")
            .accessibilityHint(expanded ? "Collapses this day" : "Expands this day")
        }
    }
}
