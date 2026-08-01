import SwiftUI
import AnalyzersKit
import UIComponents

/// Monitor pane: the bigger sibling of the menu's Monitor tab — more rows,
/// search, the same live pressure signal and Stop/Quit actions.
struct MonitorSettingsView: View {

    enum Lens: Hashable { case memory, energy, diskIO }

    @State private var lens: Lens = .memory
    @Binding var dossierPath: [DossierRoute]
    @State private var groups: [ProcessGroup] = []
    @State private var energy: [EnergyEntry] = []
    @State private var diskIO: [DiskIOEntry] = []
    @State private var pressure: LiveStats.Pressure = .normal
    /// Same instance the delegate keeps alive — one watcher, many surfaces.
    private var thermal: ThermalWatcher { ThermalWatcher.shared }
    @State private var search = ""
    @AppStorage("monitorRefreshSeconds") private var refresh = 15
    /// Standalone-process table state — the family disclosure tree below
    /// has no equivalent, since a Table can't express nesting.
    @State private var sortOrder: [KeyPathComparator<LiveProcess>] = [KeyPathComparator(\.residentMB, order: .reverse)]
    @State private var selectedPID: Int?

    /// A group matches if the parent OR any helper matches; a parent match
    /// keeps the whole family, a helper match trims to matching helpers.
    private var filtered: [ProcessGroup] {
        guard !search.isEmpty else { return groups }
        let needle = search.lowercased()
        func matches(_ proc: LiveProcess) -> Bool {
            proc.friendlyName.lowercased().contains(needle)
                || proc.rawName.lowercased().contains(needle)
        }
        return groups.compactMap { group in
            if matches(group.parent) { return group }
            let kids = group.children.filter(matches)
            return kids.isEmpty ? nil : ProcessGroup(parent: group.parent, children: kids)
        }
    }

    var body: some View {
        PaneScaffold(symbol: "gauge.with.dots.needle.67percent", color: .orange, title: "Monitor",
                     caption: "See what's using the most memory right now. These are the 30 biggest processes over 128 MB — memory in use, the number the guard acts on.") {
            Section {
                HStack {
                    Circle()
                        .fill(pressure == .normal ? .green
                              : pressure == .warning ? .orange : .red)
                        .frame(width: 8, height: 8)
                    Text("Memory pressure: \(pressure.label)")
                        .foregroundStyle(pressure == .normal ? .secondary : .primary)
                    if thermal.isElevated {
                        BadgeCapsule(text: "THROTTLING", color: .red)
                            .help("macOS is slowing the CPU to cool down — receipts in reports/thermal.log")
                    } else if thermal.state == .fair {
                        BadgeCapsule(text: "WARM", color: .orange)
                    }
                    Spacer()
                    Picker("", selection: $refresh) {
                        Text("5s").tag(5)
                        Text("15s").tag(15)
                        Text("60s").tag(60)
                        Text("Off").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }
                FullWidthSegments(
                    options: [(Lens.memory, "Memory"), (Lens.energy, "Energy"),
                              (Lens.diskIO, "Disk I/O")],
                    selection: $lens
                )
            }

            if lens == .energy {
                energySections
            } else if lens == .diskIO {
                diskIOSections
            } else if !filtered.isEmpty {
                familySection
                standaloneSection
            }
            if lens == .memory, filtered.isEmpty {
                Section {
                    Text(search.isEmpty
                         ? "No process is holding more than 128 MB right now."
                         : "No process matches “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $search, prompt: "Filter by name")
        .onChange(of: lens) { Task { await load() } }
        .task { await load() }
        .task(id: refresh) {
            guard refresh > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(refresh)))
                await load()
            }
        }
    }

    /// The two shapes the Memory lens renders: families keep their disclosure
    /// tree (a Table can't express nesting), standalone processes get the
    /// sortable Table a tree can't offer.
    private var familyGroups: [ProcessGroup] {
        filtered.filter { !$0.children.isEmpty }
    }

    private var standaloneProcs: [LiveProcess] {
        filtered.filter { $0.children.isEmpty }.map(\.parent).sorted(using: sortOrder)
    }

    @ViewBuilder private var familySection: some View {
        if !familyGroups.isEmpty {
            Section("Process families") {
                ForEach(familyGroups) { group in
                    DisclosureGroup {
                        ProcessRow(proc: group.parent) { Task { await load() } }
                        ForEach(group.children) { child in
                            ProcessRow(proc: child) { Task { await load() } }
                        }
                    } label: {
                        groupLabel(group)
                            .contextMenu {
                                Button("Dossier…") {
                                    dossierPath.append(DossierRoute(
                                        name: group.parent.friendlyName,
                                        pid: group.parent.pid))
                                }
                            }
                    }
                }
            }
        }
    }

    /// Name / Memory / PID, sortable — the standalone (non-family) rows only.
    /// Right-click restores both actions the old row offered (Dossier,
    /// Stop/Quit), since a Table cell can't host an always-visible button
    /// the way ProcessRow did.
    @ViewBuilder private var standaloneSection: some View {
        if !standaloneProcs.isEmpty {
            Section("Processes") {
                Table(standaloneProcs, selection: $selectedPID, sortOrder: $sortOrder) {
                    TableColumn("Name", sortUsing: KeyPathComparator<LiveProcess>(\.friendlyName)) { proc in
                        Text(proc.friendlyName)
                    }
                    TableColumn("Memory", sortUsing: KeyPathComparator<LiveProcess>(\.residentMB)) { proc in
                        Text(proc.residentText)
                            .foregroundStyle(proc.residentMB > 4096 ? .orange : .secondary)
                    }
                    TableColumn("PID", sortUsing: KeyPathComparator<LiveProcess>(\.pid)) { proc in
                        Text("\(proc.pid)")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)
                .contextMenu(forSelectionType: Int.self) { selection in
                    if let pid = selection.first,
                       let proc = standaloneProcs.first(where: { $0.pid == pid }) {
                        Button("Dossier…") {
                            dossierPath.append(DossierRoute(name: proc.friendlyName, pid: proc.pid))
                        }
                        Button(proc.isDev ? "Stop" : "Quit") {
                            GuardControl.stopProcess(proc)
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                await load()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Family header: real app icon when the parent is a GUI app, rolled-up
    /// total on the right — the row Activity Monitor never gives you.
    private func groupLabel(_ group: ProcessGroup) -> some View {
        HStack(spacing: 8) {
            Group {
                if let app = NSRunningApplication(processIdentifier: pid_t(group.parent.pid)),
                   let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    IconTile(symbol: "square.stack.3d.up.fill", color: .orange, side: 20)
                }
            }
            .accessibilityHidden(true) // decorative — the name text next to it already says who this is
            VStack(alignment: .leading, spacing: 1) {
                Text(group.parent.friendlyName)
                    .font(.callout.weight(.medium))
                Text("\(group.children.count) helper\(group.children.count == 1 ? "" : "s") · pid \(group.parent.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(group.totalText)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Battery blame, kernel-accounted: cumulative energy per live process.
    @ViewBuilder private var energySections: some View {
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
    @ViewBuilder private var diskIOSections: some View {
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

    private func load() async {
        switch lens {
        case .energy:
            await awaitLoad({ (EnergyStats.snapshot(limit: 30), LiveStats.memoryPressure()) }) {
                energy = $0.0
                pressure = $0.1
            }
        case .diskIO:
            await awaitLoad({ (EnergyStats.diskSnapshot(limit: 30), LiveStats.memoryPressure()) }) {
                diskIO = $0.0
                pressure = $0.1
            }
        case .memory:
            await awaitLoad({ (LiveStats.groupedSnapshot(limit: 30, minimumMB: 128),
                            LiveStats.memoryPressure()) }) {
                groups = $0.0
                pressure = $0.1
            }
        }
    }
}
