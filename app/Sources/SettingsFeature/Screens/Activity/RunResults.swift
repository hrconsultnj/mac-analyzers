import AnalyzersKit
import SwiftUI

/// A category of one run's results, as a `ScopeTabs` value: the parser's own title
/// ("Freed", "Found", "Couldn't remove"), which is stable for a kind of task.
struct RunTab: RawRepresentable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(section: ActivityOutcome.Section) { rawValue = section.title }
}

/// A run's results when its group supplies no view of its own: one category's rows in
/// the shared read-only review table, grouped under what they belong to where the
/// parser gives that as data (a project), biggest first, rows that are nothing folded
/// into one closed row. The categories are the tabs in the toolbar (`RunTabsModifier`).
struct RunResultsDefault: View {
    let section: ActivityOutcome.Section
    @State private var session: ReviewSession

    init(section: ActivityOutcome.Section) {
        self.section = section
        let rows = section.items.map {
            ReviewRow(id: "\($0.id)", name: $0.title, detail: $0.detail, group: $0.group,
                      bytes: $0.bytes, valueText: $0.bytes == nil ? $0.trailing : nil)
        }
        _session = State(initialValue: ReviewSession(readOnly: rows))
    }

    var body: some View {
        ReviewTable(session: session, readOnly: true,
                    note: section.hidden > 0 ? "and \(section.hidden.formatted()) more, smaller ones, are in the raw output" : nil)
    }
}

/// The run's categories in the toolbar when there are two or more, remembered per kind
/// of task; with one category there are no tabs.
struct RunTabsModifier: ViewModifier {
    let row: ActivityRow
    let tabs: [RunTab]
    let sections: [ActivityOutcome.Section]
    @Binding var selection: RunTab

    private func symbol(_ tone: ActivityOutcome.Tone) -> String {
        switch tone {
        case .done: "checkmark.circle"
        case .found: "magnifyingglass"
        case .alert: "exclamationmark.circle"
        case .skipped: "minus.circle"
        case .failed: "exclamationmark.triangle"
        case .info: "info.circle"
        }
    }

    @ViewBuilder func body(content: Content) -> some View {
        if (2...6).contains(sections.count), SectionRegistry.runResults(for: row) == nil {
            content.scopeTabsToolbar(
                screen: "run.\(row.kind?.rawValue ?? row.log?.rawValue ?? "other")",
                items: sections.map {
                    ScopeTabItem(value: RunTab(section: $0), title: $0.title, symbol: symbol($0.tone),
                                 count: $0.items.count + $0.hidden)
                },
                // the first category shows as selected until a person chooses another
                selection: Binding(get: { tabs.contains(selection) ? selection : tabs[0] },
                                   set: { selection = $0 }))
        } else {
            content
        }
    }
}
