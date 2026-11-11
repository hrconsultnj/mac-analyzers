import SwiftUI
import AnalyzersKit
import UIComponents

/// The Energy and Disk I/O lenses: flat tables of what macOS itself counts
/// per program since it started — who drained the battery, who wore the SSD.
extension MonitorView {

    var energyTable: some View {
        let rows = search.isEmpty ? model.energy
            : model.energy.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return OutlineTable(rows.sorted(using: energySort), children: \.noChildren, selection: $lensSelection,
                            sortOrder: $energySort, expanded: .constant([]), autosave: "monitor.energy") {
            OutlineColumn("name", Names.Monitor.name, sortUsing: KeyPathComparator(\EnergyEntry.name)) { entry in
                LensNameCell(name: entry.name, pid: entry.pid)
            }
            OutlineColumn("energy", Names.Monitor.energy, text: { $0.energyText },
                          sortUsing: KeyPathComparator(\EnergyEntry.energyNJ))
                .alignment(.trailing).monospacedDigits()
            OutlineColumn("pid", Names.Monitor.pid, text: { String($0.pid) })
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
        }
        .emptyContent(isLoading: false) { lensEmpty(rows.isEmpty, "No Energy Readings Yet", "bolt.fill") }
    }

    var diskIOTable: some View {
        let rows = search.isEmpty ? model.diskIO
            : model.diskIO.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return OutlineTable(rows.sorted(using: diskSort), children: \.noChildren, selection: $lensSelection,
                            sortOrder: $diskSort, expanded: .constant([]), autosave: "monitor.disk") {
            OutlineColumn("name", Names.Monitor.name, sortUsing: KeyPathComparator(\DiskIOEntry.name)) { entry in
                LensNameCell(name: entry.name, pid: entry.pid)
            }
            OutlineColumn("written", Names.Monitor.written, text: { $0.writtenText },
                          sortUsing: KeyPathComparator(\DiskIOEntry.bytesWritten))
                .alignment(.trailing).monospacedDigits()
            OutlineColumn("read", Names.Monitor.read, text: { $0.readText },
                          sortUsing: KeyPathComparator(\DiskIOEntry.bytesRead))
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
            OutlineColumn("pid", Names.Monitor.pid, text: { String($0.pid) })
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
        }
        .emptyContent(isLoading: false) { lensEmpty(rows.isEmpty, "No Disk Activity Readings Yet", "internaldrive") }
    }

    @ViewBuilder private func lensEmpty(_ empty: Bool, _ title: String, _ symbol: String) -> some View {
        if model.hasLoaded, empty {
            if search.isEmpty {
                ContentUnavailableView(title, systemImage: symbol)
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

/// A name with its app's icon when it is a running app.
private struct LensNameCell: View {
    let name: String
    let pid: Int

    var body: some View {
        HStack(spacing: 6) {
            if let app = NSRunningApplication(processIdentifier: pid_t(pid)), let icon = app.icon {
                // an app's own icon at row size: the icon is the actual job
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                Text(app.localizedName ?? name)
            } else {
                Text(name)
            }
        }
    }
}

/// A flat table has no rows that open: the outline asks every row for its children.
extension Identifiable {
    var noChildren: [Self]? { nil }
}
