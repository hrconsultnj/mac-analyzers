import SwiftUI
import AnalyzersKit
import UIComponents

struct DiskReclaimedDetailView: View {
    let period: TrendsModel.Period

    @State private var groups: [DiskReclaimedGroup] = []

    var body: some View {
        PaneScaffold(symbol: "internaldrive.fill", color: .indigo, title: "Disk Reclaimed",
                     caption: "Deleted build caches and node_modules in the \(period.label.lowercased()) window, grouped by project.") {
            if groups.isEmpty {
                Section {
                    Text("Nothing reclaimed in this window.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(groups) { group in
                Section {
                    DisclosureGroup {
                        ForEach(group.items) { item in
                            DataCard(symbol: "folder.fill", color: .indigo,
                                     title: item.cacheKind,
                                     subtitle: item.path,
                                     trailing: ByteSize.format(item.sizeBytes),
                                     badge: ("DELETED", .red))
                        }
                    } label: {
                        HStack {
                            IconTile(symbol: "folder.fill", color: .indigo)
                            Text(group.project).font(.callout.weight(.medium))
                            Spacer()
                            Text(ByteSize.format(group.totalBytes))
                                .font(.callout.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
        }
        .task {
            let window = period
            await awaitLoad({ TrendsModel.diskReclaimedByProject(period: window) }) { groups = $0 }
        }
    }
}
