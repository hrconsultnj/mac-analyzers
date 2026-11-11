import SwiftUI
import AnalyzersKit
import UIComponents

/// Previous runs of the selected cleaner, parsed from the logs.
extension ActionsSettingsView {

    /// One prior run of the selected cleaner, parsed — the Actions history
    /// backfill (the logs already held every run; this surfaces them here).
    struct HistoryRun: Identifiable {
        let id: Int
        let header: String
        let reap: ReapRun?
        let storage: StorageCleanRun?
        let temp: TempCleanRun?
    }

    // MARK: - history (the backfill: every prior run, parsed)

    @ViewBuilder var historySection: some View {
        if !history.isEmpty {
            Section("Previous Runs") {
                ForEach(history) { run in
                    DisclosureGroup {
                        historyCards(run)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.header)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if let summary = run.reap?.summary ?? run.storage?.summary ?? run.temp?.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func historyCards(_ run: HistoryRun) -> some View {
        if let reap = run.reap {
            ForEach(reap.allItems.prefix(15)) { item in
                DataCard(symbol: "terminal", color: statusColor(item.status),
                         title: item.friendlyName,
                         subtitle: item.description,
                         trailing: item.mb.map { "\($0) MB" },
                         badge: badge(for: item.status))
            }
        }
        if let storage = run.storage {
            ForEach(storage.items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(15)) { item in
                pathRow(item)
            }
        }
        if let temp = run.temp {
            let rows = temp.dryRun ? temp.readyItems : temp.actedItems
            ForEach(rows.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(15)) { item in
                tempRow(item)
            }
        }
    }

    func loadHistory() async {
        let logKind = cleaner.logKind
        let storageShaped = cleaner.isStorageShaped
        let tempShaped = cleaner == .tempClean
        await awaitLoad({
            LogParser.runs(for: logKind).prefix(10).enumerated().map { index, run in
                HistoryRun(id: index, header: run.header,
                           reap: storageShaped || tempShaped ? nil
                               : ReapParser.parse(runHeader: run.header, lines: run.lines),
                           storage: storageShaped
                               ? StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
                               : nil,
                           temp: tempShaped
                               ? TempCleanParser.parse(runHeader: run.header, lines: run.lines)
                               : nil)
            }
        }) { history = $0 }
    }
}
