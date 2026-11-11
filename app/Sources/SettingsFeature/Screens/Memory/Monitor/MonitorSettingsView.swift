import SwiftUI
import AnalyzersKit
import UIComponents

/// Monitor pane: the full accounting the menu's Monitor tab has no room for.
/// The Memory lens answers two questions in order — where is physical memory
/// right now, and who is holding it — over EVERY running process, grouped by
/// the app or service it belongs to. No size floor and no row cap: a process
/// too small to notice still lands in a group, and the groups add up.
struct MonitorSettingsView: View {

    enum Lens: Hashable { case memory, energy, diskIO }

    @State var lens: Lens = .memory
    @Environment(Navigator.self) var navigator
    @State var census: MemoryCensus?
    /// nil = everything; otherwise one kind of owner.
    @State var scope: CensusGroup.Category?
    /// The long tail of small groups stays folded until asked for — its
    /// total is always on screen, so nothing is hidden from the sum.
    @State var showAllFamilies = false
    @State var energy: [EnergyEntry] = []
    @State var diskIO: [DiskIOEntry] = []
    @State var pressure: LiveStats.Pressure = .normal
    /// Same instance the delegate keeps alive — one watcher, many surfaces.
    var thermal: ThermalWatcher { ThermalWatcher.shared }
    @State var search = ""
    @FocusState var searchFocused: Bool
    @AppStorage("monitorRefreshSeconds") var refresh = 15
    /// Standalone-process table state — the family disclosure tree below
    /// has no equivalent, since a Table can't express nesting.
    @State var sortOrder: [KeyPathComparator<LiveProcess>] = [KeyPathComparator(\.memoryBytes, order: .reverse)]
    @State var selectedPID: Int?

    /// How many families show before the tail folds into one summary row.
    static let familyFold = 20

    /// A group matches if its NAME or any process in it matches; a name match
    /// keeps the whole family, a process match trims to the ones that matched.
    var filtered: [CensusGroup] {
        let groups = census?.groups(in: scope) ?? []
        guard !search.isEmpty else { return groups }
        let needle = search.lowercased()
        func matches(_ proc: LiveProcess) -> Bool {
            proc.friendlyName.lowercased().contains(needle)
                || proc.rawName.lowercased().contains(needle)
        }
        return groups.compactMap { group in
            if group.name.lowercased().contains(needle)
                || group.role?.lowercased().contains(needle) == true { return group }
            let kept = group.members.filter(matches)
            return kept.isEmpty ? nil : group.keeping(kept)
        }
    }

    var body: some View {
        PaneScaffold(symbol: "gauge.with.dots.needle.67percent", color: .orange, title: Names.Screen.monitor,
                     caption: "Where your memory is and who is holding it — every running process, grouped by the app or service it belongs to. Nothing is left out for being small.") {
            Section {
                HStack {
                    Circle()
                        .fill(pressure == .normal ? .green
                              : pressure == .warning ? .orange : .red)
                        .frame(width: 8, height: 8)
                    Text("Memory Pressure: \(pressure.label)")
                        .foregroundStyle(pressure == .normal ? .secondary : .primary)
                    if thermal.isElevated {
                        BadgeCapsule(text: "Throttling", color: .red)
                            .help("macOS is slowing the CPU to cool down — receipts in reports/thermal.log")
                    } else if thermal.state == .fair {
                        BadgeCapsule(text: "Warm", color: .orange)
                    }
                    Spacer()
                    Picker("", selection: $refresh) {
                        Text("5 s").tag(5)
                        Text("15 s").tag(15)
                        Text("60 s").tag(60)
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
            } else {
                breakdownSection
                ledgerSection
                if !filtered.isEmpty {
                    familySection
                    standaloneSection
                }
            }
            if lens == .memory, census != nil, filtered.isEmpty {
                Section {
                    Text(search.isEmpty
                         ? "Nothing is running in this group right now."
                         : "No process matches “\(search)”.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $search, prompt: "Filter by name")
        .searchFocused($searchFocused)
        .screenActions(refresh: { Task { await load() } },
                       find: { searchFocused = true },
                       isActive: navigator.path.isEmpty)
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
    var familyGroups: [CensusGroup] {
        filtered.filter { $0.members.count > 1 }
    }

    var standaloneProcs: [LiveProcess] {
        filtered.filter { $0.members.count == 1 }.map { $0.members[0] }.sorted(using: sortOrder)
    }

    /// The polite request, then a refresh once macOS has had time to act on
    /// it — the same behaviour ProcessRow had before the table.
    func stop(_ proc: LiveProcess) {
        GuardControl.stopProcess(proc)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await load()
        }
    }

    func load() async {
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
            await awaitLoad({ (MemoryCensus.take(), LiveStats.memoryPressure()) }) {
                census = $0.0
                pressure = $0.1
            }
        }
    }
}
