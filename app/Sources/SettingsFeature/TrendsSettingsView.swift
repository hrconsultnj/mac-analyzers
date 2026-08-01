import SwiftUI
import Charts
import AnalyzersKit
import UIComponents

/// Trends pane: what the suite has actually done over time — the receipts,
/// aggregated. Headline sentence, defended/recovered stat tiles, events-per-
/// day chart, and the repeat offenders. All read from local logs.
struct TrendsSettingsView: View {

    @State private var period: TrendsModel.Period = .day30
    @State private var snapshot: TrendsSnapshot?

    private var extendedSelected: Bool {
        TrendsModel.Period.extended.contains(period)
    }

    var body: some View {
        PaneScaffold(symbol: "chart.xyaxis.line", color: .mint, title: "Trends",
                     caption: "What the guard and cleaners have done for this Mac — from its own logs, nothing leaves the machine.") {
            Section {
                // 3/7/30 fill the bar; the fixed-width ellipsis is a menu
                // holding the longer (and shorter) ranges
                HStack(spacing: 8) {
                    FullWidthSegments(
                        options: TrendsModel.Period.primary.map { ($0, $0.label) },
                        selection: $period
                    )
                    Menu {
                        ForEach(TrendsModel.Period.extended, id: \.self) { option in
                            Button {
                                period = option
                            } label: {
                                if period == option {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .fontWeight(.semibold)
                            .frame(width: 34, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(extendedSelected ? Color.white : .secondary)
                    .background(extendedSelected ? Color.accentColor : Color.clear,
                                in: Capsule())
                    .help(extendedSelected ? period.label : "More ranges")
                }
                if extendedSelected {
                    Text("Showing: \(period.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let snap = snapshot {
                Section {
                    Text(snap.headline)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                }
                if snap.isEmpty {
                    Section {
                        Text("No activity in this window yet — trends fill in as the agents run.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    statSections(snap)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: period) { load() }
    }

    @ViewBuilder private func statSections(_ snap: TrendsSnapshot) -> some View {
        Section("Defended") {
            statGrid([
                ("xmark.octagon.fill", .red, "\(snap.kills)", "Runaways stopped"),
                ("arrow.up.right", .orange, "\(snap.spikes)", "Spikes caught"),
                ("exclamationmark.triangle.fill", .orange, "\(snap.pressure)", "Pressure alerts"),
                ("cpu", .purple, "\(snap.cpuHogs)", "CPU hogs flagged"),
            ])
        }
        Section("Recovered") {
            statGrid([
                ("memorychip", .blue,
                 String(format: "%.1f GB", Double(snap.memoryFreedMB) / 1024), "Memory freed"),
                ("internaldrive.fill", .indigo,
                 ByteSize.format(snap.storageFreedBytes), "Disk reclaimed"),
                ("sparkles", .teal,
                 ByteSize.format(snap.latestReclaimableBytes), "Reclaimable right now"),
            ])
        }
        if !snap.days.isEmpty {
            Section("Guard events per day") {
                Chart(snap.days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value("Kills", day.kills))
                        .foregroundStyle(by: .value("Type", "Killed"))
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value("Spikes", day.spikes))
                        .foregroundStyle(by: .value("Type", "Spikes"))
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value("Other", day.other))
                        .foregroundStyle(by: .value("Type", "Other"))
                }
                .chartForegroundStyleScale([
                    "Killed": Color.red, "Spikes": Color.orange, "Other": Color.purple,
                ])
                .frame(height: 150)
                .padding(.vertical, 4)
            }
        }
        if !snap.offenders.isEmpty {
            Section("Repeat offenders") {
                ForEach(snap.offenders) { offender in
                    DataCard(symbol: "flame.fill", color: .orange,
                             title: offender.name,
                             subtitle: "\(offender.count) event\(offender.count == 1 ? "" : "s") in this window",
                             trailing: "\(offender.count)×",
                             badge: offender.kills > 0
                                 ? ("\(offender.kills) KILLED", .red) : nil)
                }
            }
        }
    }

    private func statGrid(_ stats: [(symbol: String, color: Color, value: String, label: String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                 count: min(stats.count, 4)),
                  spacing: 10) {
            ForEach(stats, id: \.label) { stat in
                VStack(spacing: 3) {
                    Image(systemName: stat.symbol)
                        .foregroundStyle(stat.color)
                        .font(.body)
                    Text(stat.value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 2)
    }

    private func load() {
        snapshot = TrendsModel.snapshot(period: period)
    }
}
