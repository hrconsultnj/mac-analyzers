import SwiftUI
import AnalyzersKit

/// The Energy and Disk I/O lenses: flat tables of what macOS itself counts
/// per program since it started — who drained the battery, who wore the SSD.
extension MonitorView {

    var energyTable: some View {
        let rows = search.isEmpty ? model.energy
            : model.energy.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return Table(rows.sorted(using: energySort), sortOrder: $energySort) {
            TableColumn(Names.Monitor.name) { entry in LensNameCell(name: entry.name, pid: entry.pid) }
            TableColumn(Names.Monitor.energy, value: \.energyNJ) { entry in
                Text(entry.energyText).monospacedDigit()
            }
            TableColumn(Names.Monitor.pid) { entry in
                Text(String(entry.pid)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .overlay { lensEmpty(rows.isEmpty, "No Energy Readings Yet", "bolt.fill") }
    }

    var diskIOTable: some View {
        let rows = search.isEmpty ? model.diskIO
            : model.diskIO.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return Table(rows.sorted(using: diskSort), sortOrder: $diskSort) {
            TableColumn(Names.Monitor.name) { entry in LensNameCell(name: entry.name, pid: entry.pid) }
            TableColumn(Names.Monitor.written, value: \.bytesWritten) { entry in
                Text(entry.writtenText).monospacedDigit()
            }
            TableColumn(Names.Monitor.read, value: \.bytesRead) { entry in
                Text(entry.readText).monospacedDigit().foregroundStyle(.secondary)
            }
            TableColumn(Names.Monitor.pid) { entry in
                Text(String(entry.pid)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .overlay { lensEmpty(rows.isEmpty, "No Disk Activity Readings Yet", "internaldrive") }
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
