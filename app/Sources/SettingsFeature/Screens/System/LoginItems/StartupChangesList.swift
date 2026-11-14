import AnalyzersKit
import SwiftUI

/// What was added to startup, newest day first, with a count per day. A row
/// that the audit also knows opens that item in the table.
struct StartupChangesList: View {
    let changes: [StartupChange]
    let inventory: StartupInventory?
    @Binding var selection: StartupChange.ID?
    let onShowInItems: (StartupItem) -> Void
    let onShowInFinder: (String) -> Void

    private struct Day: Identifiable {
        let date: Date
        let changes: [StartupChange]
        var id: Date { date }
    }

    /// The newest 200 changes; "Show Older" adds 200 more. A list never gains
    /// more than that in one update.
    @State private var limit = 200

    private var days: [Day] {
        Dictionary(grouping: changes.prefix(limit)) { Calendar.current.startOfDay(for: $0.date) }
            .map { Day(date: $0.key, changes: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(days) { day in
                Section {
                    ForEach(day.changes) { change in
                        row(change).tag(change.id)
                    }
                } header: {
                    HStack {
                        Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        Spacer()
                        Text("\(day.changes.count) \(day.changes.count == 1 ? "change" : "changes")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if changes.count > limit {
                Button("Show Older (\(changes.count - limit) more)") { limit += 200 }
            }
        }
        .contextMenu(forSelectionType: StartupChange.ID.self) { ids in
            if let change = single(ids), let path = change.path {
                if let item = change.item(in: inventory) {
                    Button("Show in Items") { onShowInItems(item) }
                }
                Button("Show in Finder") { onShowInFinder(path) }
                    .disabled(!change.stillInstalled)
            }
        } primaryAction: { ids in
            if let change = single(ids), let item = change.item(in: inventory) { onShowInItems(item) }
        }
        .overlay {
            if changes.isEmpty {
                EmptyState("No Changes Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Anything that adds itself to startup will be listed here."))
            }
        }
    }

    private func row(_ change: StartupChange) -> some View {
        LabeledContent {
            VStack(alignment: .trailing) {
                Text(change.date.formatted(date: .omitted, time: .shortened))
                if change.path != nil {
                    Text(change.stillInstalled ? "Still installed" : "Gone")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(change.title)
                    Text(change.detail).font(.callout).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: change.path == nil ? "eye" : "plus.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func single(_ ids: Set<StartupChange.ID>) -> StartupChange? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return changes.first { $0.id == id }
    }
}
