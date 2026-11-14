import AnalyzersKit
import SwiftUI
import UIComponents

/// The reports of one kind, a section per month with what the month adds up
/// to. The newest month starts open; clicking a month's header folds it.
///
/// A header button hides the rows rather than using `Section(isExpanded:)`,
/// which only collapses in the sidebar list style.
struct ReportList: View {
    let months: [ReportMonth]
    @Binding var selection: ReportDocument.ID?
    /// The months that are open, kept across window close and relaunch (the newest starts open).
    let expansion: RememberedExpansion<String>
    let onShowInFinder: (ReportDocument) -> Void

    /// A month's id in the remembered set: "2026-10".
    static func key(_ month: ReportMonth) -> String { month.date.formatted(.iso8601.year().month()) }

    var body: some View {
        List(selection: $selection) {
            ForEach(months) { month in
                let isOpen = expansion.ids.contains(ReportList.key(month))
                Section {
                    if isOpen {
                        ForEach(month.reports) { report in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(report.title)
                                    Text("\(report.whenWritten) · \(ByteSize.format(report.fileSize))")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: report.kind.symbol).foregroundStyle(.secondary)
                            }
                            .tag(report.id)
                            .contextMenu { Button("Show in Finder") { onShowInFinder(report) } }
                        }
                    }
                } header: {
                    Button {
                        let open = expansion.binding
                        if isOpen { open.wrappedValue.remove(ReportList.key(month)) }
                        else { open.wrappedValue.insert(ReportList.key(month)) }
                    } label: {
                        HStack {
                            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.secondary)
                            Text(month.date.formatted(.dateTime.month(.wide).year()))
                            Spacer()
                            Text(month.summary).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isOpen ? "Folds this month" : "Opens this month")
                }
            }
        }
        .overlay {
            if months.isEmpty {
                EmptyState("No Reports Yet", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Write a report to see it here."))
            }
        }
    }
}
