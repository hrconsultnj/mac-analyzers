import SwiftUI
import Charts
import AnalyzersKit
import UIComponents

/// The dashboard's sections: defended and recovered tiles, the chart, the offenders.
extension TrendsSettingsView {

    /// Memory: what the guard and the cleanups did about running processes.
    @ViewBuilder func memorySections(_ snap: TrendsSnapshot) -> some View {
        Section("Defended") {
            tiles([
                ("xmark.octagon.fill", .red, "\(snap.kills)", "Runaways Stopped", .kills(snap.period)),
                ("arrow.up.right", .orange, "\(snap.spikes)", "Spikes Caught", .spikes(snap.period)),
                ("exclamationmark.triangle.fill", .orange, "\(snap.pressure)", "Pressure Alerts", .pressure(snap.period)),
                ("cpu", .purple, "\(snap.cpuHogs)", "CPU Hogs Flagged", .cpuHogs(snap.period)),
                ("memorychip", .blue, MemorySize.text(Int64(snap.memoryFreedMB) * 1_048_576),
                 "Memory Freed", .memoryFreed(snap.period)),
            ])
        }
        if snap.buckets.contains(where: { $0.events > 0 }) {
            Section("Guard Events per \(snap.period.bucket == .hour ? "Hour" : "Day")") {
                EventsChart(buckets: snap.buckets, period: snap.period,
                            summary: "\(snap.kills) killed, \(snap.spikes) spikes, \(snap.period.phrase)")
            }
        }
        if snap.memoryFreedMB > 0 {
            Section("Memory Freed per \(snap.period.bucket == .hour ? "Hour" : "Day")") {
                ValueChart(buckets: snap.buckets, period: snap.period, name: "Memory Freed", color: .blue,
                           value: { Double($0.freedMB) },
                           format: { MemorySize.text(Int64($0) * 1_048_576) })
            }
        }
        if !snap.offenders.isEmpty {
            Section("Repeat Offenders") {
                ForEach(snap.offenders) { offender in
                    OverviewRow(action: { navigator.push(.history(.trends(.offender(offender.name, snap.period)))) }) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(offender.name)
                                Text("\(offender.count) \(offender.count == 1 ? "event" : "events")"
                                     + (offender.kills > 0 ? ", \(offender.kills) stopped" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    /// Storage: what the cleanups removed, by project (level 3), and what they could remove now.
    @ViewBuilder func storageSections(_ snap: TrendsSnapshot) -> some View {
        Section {
            tiles([
                ("internaldrive.fill", .indigo, ByteSize.format(snap.storageFreedBytes),
                 "Removed by Cleanups", .diskReclaimed(snap.period)),
                ("sparkles", .teal, snap.latestReclaimableBytes.map(ByteSize.format) ?? "—",
                 "Reclaimable Now", .reclaimableNow),
            ])
        } header: {
            Text("Recovered")
        } footer: {
            Text("Removed by Cleanups adds up everything the cleanups deleted, including folders that were rebuilt and removed again. It is not the net space gained.")
        }
        if snap.storageFreedBytes > 0 {
            Section("Removed per \(snap.period.bucket == .hour ? "Hour" : "Day")") {
                ValueChart(buckets: snap.buckets, period: snap.period, name: "Removed", color: .indigo,
                           value: { Double($0.removedBytes) }, format: { ByteSize.format(Int64($0)) })
            }
        }
        if !projects.isEmpty {
            // plain rows, not a second opening list: each opens the table above's detail at that project
            Section("Removed by Project") {
                ForEach(projects.prefix(12)) { group in
                    OverviewRow(action: { navigator.push(.history(.trends(.removedProject(group.project, snap.period)))) }) {
                        HStack {
                            Text(group.project).fontWeight(.medium)
                            Text("\(group.items.count) \(group.items.count == 1 ? "item" : "items")")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(ByteSize.format(group.totalBytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if projects.count > 12 {
                    OverviewRow(action: { navigator.push(.history(.trends(.diskReclaimed(snap.period)))) }) {
                        Text("\(projects.count - 12) more projects")
                    }
                }
            }
        }
    }

    /// One row of native buttons; each opens its detail table.
    private func tiles(_ stats: [(symbol: String, color: Color, value: String, label: String, route: TrendsRoute)]) -> some View {
        HStack(spacing: 10) {
            ForEach(stats, id: \.label) { stat in
                Button { navigator.push(.history(.trends(stat.route))) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: stat.symbol).foregroundStyle(stat.color)
                            .accessibilityHidden(true)  // the value and label say the same
                        Text(stat.value).font(.title3.weight(.semibold).monospacedDigit())
                        Text(stat.label).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonSizing(.flexible)
            }
        }
        // a row of buttons, not a list row: no separator under it
        .listRowSeparator(.hidden)
    }
}
