import AnalyzersKit
import SwiftUI

/// Every saved snapshot, newest day first with a count per day. A row opens
/// that snapshot in the table.
struct NetworkHistoryList: View {
    let snapshots: [NetworkSnapshotRun]
    @Binding var selection: NetworkSnapshotRun.ID?
    let onOpen: (NetworkSnapshotRun) -> Void

    private struct Day: Identifiable {
        let date: Date
        let snapshots: [NetworkSnapshotRun]
        var id: Date { date }
    }

    private var days: [Day] {
        Dictionary(grouping: snapshots) { Calendar.current.startOfDay(for: $0.date) }
            .map { Day(date: $0.key, snapshots: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(days) { day in
                Section {
                    ForEach(day.snapshots) { run in row(run).tag(run.id) }
                } header: {
                    HStack {
                        Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        Spacer()
                        Text("\(day.snapshots.count) \(day.snapshots.count == 1 ? "snapshot" : "snapshots")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: NetworkSnapshotRun.ID.self) { ids in
            if let run = single(ids) { Button("Open Snapshot") { onOpen(run) } }
        } primaryAction: { ids in
            if let run = single(ids) { onOpen(run) }
        }
        .overlay {
            if snapshots.isEmpty {
                ContentUnavailableView("No Snapshots Yet", systemImage: "network",
                                       description: Text("Take a snapshot to see which programs have been using the network."))
            }
        }
    }

    private func row(_ run: NetworkSnapshotRun) -> some View {
        LabeledContent {
            Text(run.date.formatted(date: .omitted, time: .shortened))
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text("\(ByteSize.format(run.totalDownloaded)) downloaded, \(ByteSize.format(run.totalUploaded)) uploaded")
                    Text("\(run.processCount) programs" + (run.busiest.map { ", busiest was \($0)" } ?? ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "network").foregroundStyle(.secondary)
            }
        }
    }

    private func single(_ ids: Set<NetworkSnapshotRun.ID>) -> NetworkSnapshotRun? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return snapshots.first { $0.id == id }
    }
}
