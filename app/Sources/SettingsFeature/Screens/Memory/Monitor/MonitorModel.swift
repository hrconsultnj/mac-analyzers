import AppKit
import SwiftUI
import AnalyzersKit

/// What Monitor shows and how it stays current. The rows come from
/// `MonitorTree`; this holds them between refreshes under the one rule that
/// matters for a live table: a refresh updates values in place and never
/// re-orders (prototype gate 1: re-ordering under a live table trips AppKit's
/// reentrant-delegate warning, and moves a row out from under the pointer).
/// Rows re-order when the person changes the sort, presses Refresh, or after
/// ten quiet seconds with the pointer off the table.
@MainActor @Observable
final class MonitorModel {

    enum Lens: String, CaseIterable, Identifiable {
        case memory = "Memory"
        case energy = "Energy"
        case diskIO = "Disk I/O"
        var id: String { rawValue }
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

    // expansion, remembered between launches by row id
    private static let expandedKey = "monitor.expanded"
    /// Not observed, on purpose: the table owns what is open once it is built,
    /// and this only seeds it and records what the person opens. Observed, a
    /// click on a row's arrow wrote here from inside AppKit's own callback, the
    /// write re-ran the table's body, and AppKit logged "reentrant operation
    /// in its NSTableView delegate" on every open (measured).
    @ObservationIgnored var expanded: Set<String> = Set(UserDefaults.standard.stringArray(forKey: MonitorModel.expandedKey) ?? [])
    {
        didSet { UserDefaults.standard.set(Array(expanded), forKey: MonitorModel.expandedKey) }
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
                            : MonitorTree.merge(rows, with: fresh, open: expanded)
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
        rows = MonitorTree.merge(rows, with: MonitorTree.rows(census: census, cpu: cpu), open: expanded)
    }

    // MARK: - ordering

    /// The person chose a column to sort by.
    func setSort(_ new: MonitorTree.Sort) {
        guard new != sort else { return }
        sort = new
        resort()
    }

    /// Bumped when the order really changed. A table that is re-ordered in
    /// place makes AppKit log "reentrant operation in its NSTableView
    /// delegate" every time (measured: three sorts, three warnings, with or
    /// without animation); a table built fresh in the new order does not. The
    /// view reads this as the table's identity, so a re-order is a rebuild —
    /// expansion and selection live here and in the view, so they survive it.
    private(set) var orderGeneration = 0

    func resort() {
        let before = MonitorTree.order(of: rows)
        var latest = rows
        // the person asked for this: take the rows as they are NOW as well
        if let census = lastCensus {
            latest = MonitorTree.merge(rows, with: MonitorTree.rows(census: census, cpu: lastCPU))
        }
        let sortedRows = MonitorTree.sorted(latest, by: sort)
        rows = sortedRows
        if MonitorTree.order(of: sortedRows) != before { orderGeneration += 1 }
    }

    // MARK: - icons

    private func readIcons() {
        var found = icons
        for row in rows where row.category == .apps {
            if let pid = row.iconPID,
               let image = NSRunningApplication(processIdentifier: pid_t(pid))?.icon {
                found[row.id] = image
            }
        }
        icons = found
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

    /// Opens every row at once — a rebuild, because opening hundreds of rows in
    /// place is another change AppKit warns about (opening one by hand is not).
    func expandEverything() {
        func open(_ rows: [MonitorRow]) {
            for row in rows where row.hasChildren { expanded.insert(row.id); open(row.children) }
        }
        open(rows)
        rebuildTable()
    }

    /// Builds the table afresh (to show a change made outside its own clicks).
    func rebuildTable() { orderGeneration += 1 }

    func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(get: { self.expanded.contains(id) },
                set: { open in
                    if open { self.expanded.insert(id) } else { self.expanded.remove(id) }
                })
    }

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
