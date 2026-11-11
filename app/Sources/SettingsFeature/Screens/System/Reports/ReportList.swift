import AnalyzersKit
import SwiftUI

/// The reports of one kind, a section per month with what the month adds up
/// to. The newest month starts open; clicking a month's header folds it.
///
/// A header button hides the rows rather than using `Section(isExpanded:)`,
/// which only collapses in the sidebar list style.
struct ReportList: View {
    let months: [ReportMonth]
    @Binding var selection: ReportDocument.ID?
    /// Months the person opened or closed; a month nobody touched is open only
    /// when it is the newest.
    @Binding var opened: [ReportMonth.ID: Bool]
    let onShowInFinder: (ReportDocument) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                let isOpen = opened[month.id] ?? (index == 0)
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
                    Button { opened[month.id] = !isOpen } label: {
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
                ContentUnavailableView("No Reports Yet", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Write a report to see it here."))
            }
        }
    }
}
