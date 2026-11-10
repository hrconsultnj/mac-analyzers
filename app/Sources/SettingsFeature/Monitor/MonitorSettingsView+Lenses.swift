import SwiftUI
import AnalyzersKit
import UIComponents

/// The Energy and Disk I/O lenses.
extension MonitorSettingsView {

    /// Battery blame, kernel-accounted: cumulative energy per live process.
    @ViewBuilder var energySections: some View {
        let rows = search.isEmpty ? energy : energy.filter {
            $0.name.lowercased().contains(search.lowercased())
        }
        Section("Energy since launch (the numbers macOS itself reports — who drained the battery)") {
            if rows.isEmpty {
                Text("No energy accounting available yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { entry in
                if let app = NSRunningApplication(processIdentifier: pid_t(entry.pid)),
                   let icon = app.icon {
                    DataCard(appIcon: icon, title: app.localizedName ?? entry.name,
                             subtitle: "pid \(entry.pid)",
                             trailing: entry.energyText)
                } else {
                    DataCard(symbol: "bolt.fill", color: .yellow,
                             title: entry.name,
                             subtitle: "pid \(entry.pid)",
                             trailing: entry.energyText)
                }
            }
        }
    }

    /// SSD wear, kernel-accounted: cumulative bytes read/written per process.
    @ViewBuilder var diskIOSections: some View {
        let rows = search.isEmpty ? diskIO : diskIO.filter {
            $0.name.lowercased().contains(search.lowercased())
        }
        Section("Disk I/O since launch (writes are what wear the SSD)") {
            if rows.isEmpty {
                Text("No disk-I/O accounting available yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { entry in
                if let app = NSRunningApplication(processIdentifier: pid_t(entry.pid)),
                   let icon = app.icon {
                    DataCard(appIcon: icon, title: app.localizedName ?? entry.name,
                             subtitle: "↓ \(entry.readText) read · pid \(entry.pid)",
                             trailing: "↑ \(entry.writtenText)")
                } else {
                    DataCard(symbol: "internaldrive", color: .indigo,
                             title: entry.name,
                             subtitle: "↓ \(entry.readText) read · pid \(entry.pid)",
                             trailing: "↑ \(entry.writtenText)")
                }
            }
        }
    }
}
