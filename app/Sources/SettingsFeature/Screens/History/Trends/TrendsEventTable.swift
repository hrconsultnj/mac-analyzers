import SwiftUI
import AnalyzersKit
import UIComponents

/// Guard events as a sortable table: when, which app, what happened, how much
/// memory. The same rows the Overview and the menu-bar panel list.
struct TrendsEventTable: View {
    let rows: [OverviewModel.EventRow]
    let emptyTitle: String
    @Environment(Navigator.self) private var navigator
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\OverviewModel.EventRow.when, order: .reverse)]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle",
                                   description: Text("Nothing was recorded in this period."))
        } else {
            Table(rows.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("When", value: \.when) { row in
                    Text(row.when, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .monospacedDigit()
                }
                .width(min: 110, ideal: 130)
                TableColumn("Name", value: \.title) { row in
                    Label(row.title, systemImage: row.event.symbol).foregroundStyle(row.event.tint)
                }
                .width(min: 150, ideal: 220)
                TableColumn("What Happened") { row in Text(row.outcome) }
                    .width(min: 260, ideal: 460)
                TableColumn("Memory") { row in
                    Text(row.event.residentText ?? "—").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 80)
            }
            .contextMenu(forSelectionType: String.self) { _ in
                Button("Open \(Names.Screen.memoryGuard)") { navigator.open(target: "log:guardLog") }
            } primaryAction: { _ in
                navigator.open(target: "log:guardLog")   // double-click or Return
            }
        }
    }
}
