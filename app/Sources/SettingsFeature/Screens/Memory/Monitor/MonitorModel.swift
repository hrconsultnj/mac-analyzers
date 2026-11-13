import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// What Monitor shows and how it stays current. The rows come from
/// `MonitorTree`; this holds them between refreshes under one product rule: a
/// refresh updates values and membership in place and never re-orders, because
/// a row must not slide away from under the pointer. Rows re-order only when the
/// person changes the sort or presses Refresh. (The table itself would take a
/// re-order live, keeping scroll position, selection and focus.)
@MainActor @Observable
final class MonitorModel {

    enum Lens: String, CaseIterable, Identifiable {
        case memory, energy, diskIO
        var id: String { rawValue }
        var title: String {
            switch self {
            case .memory: Names.Monitor.lensMemory
            case .energy: Names.Monitor.lensEnergy
            case .diskIO: Names.Monitor.lensDisk
            }
        }
        var symbol: String {
            switch self {
            case .memory: "memorychip"
            case .energy: "bolt.fill"
            case .diskIO: "internaldrive"
            }
        }
    }

    // what the table shows
    private(set) var rows: [MonitorRow] = []
    private(set) var energy: [EnergyEntry] = []
    private(set) var diskIO: [DiskIOEntry] = []
    private(set) var breakdown: MemoryBreakdown?
    private(set) var pressure: LiveStats.Pressure = .normal
    private(set) var processCount = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var unmeasured = 0
    private(set) var hasLoaded = false
    /// Which lenses have shown rows at least once.
    private var loaded: Set<Lens> = []
    func isLoaded(_ lens: Lens) -> Bool { loaded.contains(lens) }
    /// Icons of the apps that are running, by row id — read once per refresh
    /// rather than once per redraw.
    private(set) var icons: [String: NSImage] = [:]

    var lens: Lens = .memory
    /// The sort the person chose; applied only when they choose it, press
    /// Refresh, or the table has been left alone for a while.
    private(set) var sort = MonitorTree.Sort.biggestFirst

    /// Which groups are open, remembered across window close and relaunch by row id.
    let expansion = MonitorModel.rememberedGroups()

    /// The groups the first Monitor left open (`monitor.expanded`) move to the shared store once, before it
    /// is read, and count as the person's own choice, so the screen's default never replaces them.
    private static func rememberedGroups() -> RememberedExpansion<String> {
        let defaults = UserDefaults.standard
        if let old = defaults.stringArray(forKey: "monitor.expanded") {
            if defaults.object(forKey: "outline.expanded.monitor") == nil {
                defaults.set(old, forKey: "outline.expanded.monitor")
                defaults.set(true, forKey: "outline.expanded.monitor.touched")
            }
            defaults.removeObject(forKey: "monitor.expanded")
        }
        return RememberedExpansion<String>(screen: "monitor")
    }

    private var meter = CPUMeter()
    private var lastCPU: [Int: Double] = [:]
    private var lastCensus: MemoryCensus?

    // MARK: - refreshing

    /// A tick: new values, same order.
    /// `force` skips the load coordinator's three-second memory of the last
    /// answer: Refresh Now, and the look after a Stop, must read the process
    /// table again, not repeat what it said a moment ago.
    func refresh(force: Bool = false) async {
        let ttl: TimeInterval = force ? 0 : 3
        switch lens {
        case .memory:
            await awaitLoad({ (MemoryCensus.take(), LiveStats.memoryPressure()) },
                            ttl: ttl, key: "monitor.census") { loaded in
                apply(census: loaded.0, pressure: loaded.1)
            }
            await primeCPUIfNeeded()
        case .energy:
            await awaitLoad({ (EnergyStats.snapshot(limit: 60), LiveStats.memoryPressure()) },
                            ttl: ttl, key: "monitor.energy") { energy = $0.0; pressure = $0.1; hasLoaded = true; loaded.insert(.energy) }
        case .diskIO:
            await awaitLoad({ (EnergyStats.diskSnapshot(limit: 60), LiveStats.memoryPressure()) },
                            ttl: ttl, key: "monitor.diskio") { diskIO = $0.0; pressure = $0.1; hasLoaded = true; loaded.insert(.diskIO) }
        }
    }

    /// Refresh Now: new values AND a fresh sort.
    func refreshNow() async {
        await refresh(force: true)
        resort()
    }

    private func apply(census: MemoryCensus, pressure: LiveStats.Pressure) {
        lastCensus = census
        self.pressure = pressure
        breakdown = census.breakdown
        processCount = census.processCount
        totalBytes = census.totalBytes
        unmeasured = census.unmeasuredCount

        let pids = census.groups.flatMap { $0.members.map { Int32($0.pid) } }
        let cpu = meter.look(at: ProcTable.cpuTimes(of: pids))
        lastCPU = cpu
        let fresh = MonitorTree.rows(census: census, cpu: cpu)
        rows = rows.isEmpty ? MonitorTree.sorted(fresh, by: sort)
                            : MonitorTree.merge(rows, with: fresh)
        readIcons()
        hasLoaded = true
        loaded.insert(.memory)
    }

    /// The first look has nothing to compare with, so CPU would stay empty for
    /// a whole refresh interval. One second later, look again.
    private var cpuPrimed = false
    private func primeCPUIfNeeded() async {
        guard !cpuPrimed, let census = lastCensus else { return }
        cpuPrimed = true
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        let pids = census.groups.flatMap { $0.members.map { Int32($0.pid) } }
        let times = await Task.detached(priority: .utility) { ProcTable.cpuTimes(of: pids) }.value
        let cpu = meter.look(at: times)
        lastCPU = cpu
        rows = MonitorTree.merge(rows, with: MonitorTree.rows(census: census, cpu: cpu))
    }

    // MARK: - ordering

    /// The person chose a column to sort by.
    func setSort(_ new: MonitorTree.Sort) {
        guard new != sort else { return }
        sort = new
        resort()
    }

    func resort() {
        var latest = rows
        // the person asked for this: take the rows as they are NOW as well
        if let census = lastCensus {
            latest = MonitorTree.merge(rows, with: MonitorTree.rows(census: census, cpu: lastCPU))
        }
        rows = MonitorTree.sorted(latest, by: sort)
    }

    // MARK: - icons

    private func readIcons() {
        var found = icons
        for row in rows where row.category == .apps {
            // the same lookup as the menu-bar panel's: an app whose main process is a helper still has its bundle's icon
            if let pid = row.iconPID, let image = GroupIcon.image(forAppPID: pid) {
                found[row.id] = image
            }
        }
        icons = found
    }

    /// Replaces the rows (what a refresh does, minus the census): the headless probe uses it to start and
    /// end processes inside an open group without waiting for real ones.
    func setRows(_ new: [MonitorRow]) {
        rows = new
        hasLoaded = true
        loaded.insert(.memory)
    }

    // MARK: - what the screen asks

    func row(_ id: MonitorRow.ID?) -> MonitorRow? {
        guard let id else { return nil }
        func search(_ rows: [MonitorRow]) -> MonitorRow? {
            for row in rows {
                if row.id == id { return row }
                if let inner = search(row.children) { return inner }
            }
            return nil
        }
        return search(rows)
    }

    /// Opens every group at once.
    func expandEverything() {
        func open(_ rows: [MonitorRow]) -> Set<String> {
            rows.filter(\.hasChildren).reduce(into: Set<String>()) { $0.insert($1.id); $0.formUnion(open($1.children)) }
        }
        expansion.ids.formUnion(open(rows))
    }

    /// Opens these groups, keeping whatever else is open.
    func open(_ ids: some Sequence<String>) { expansion.ids.formUnion(ids) }

    /// "1,145 processes · 24.7 GB in use".
    var subtitle: String {
        switch lens {
        case .memory:
            guard hasLoaded else { return "Reading the process table…" }
            let used = breakdown.map { MemorySize.text($0.usedBytes) }
                ?? MemorySize.text(totalBytes)
            return "\(processCount.formatted()) processes · \(used)"
        case .energy: return "Energy since each program started"
        case .diskIO: return "Disk activity since each program started"
        }
    }
}
