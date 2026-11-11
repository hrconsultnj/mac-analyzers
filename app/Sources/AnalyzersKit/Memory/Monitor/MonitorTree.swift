import Foundation

/// Monitor's table as pure functions over the census: build the tree, update
/// it in place on a refresh, sort it, filter it. No view code, so
/// `agent-runner --probe-monitor` prints exactly the rows the screen shows.
///
/// The refresh rule (prototype gate 1): a tick replaces the VALUES of rows
/// that already exist and never re-orders them — re-sorting under a live
/// table triggers AppKit's reentrant-delegate warning and, worse, moves a row
/// out from under the pointer. Rows move only when the person changes the
/// sort or presses Refresh.
public enum MonitorTree {

    // MARK: - building

    public static func rows(census: MemoryCensus, cpu: [Int: Double] = [:]) -> [MonitorRow] {
        census.groups.map { groupRow($0, cpu: cpu) }
    }

    private static func groupRow(_ group: CensusGroup, cpu: [Int: Double]) -> MonitorRow {
        let id = "group:\(group.id)"
        let children: [MonitorRow]
        let detail: String
        var stop: MonitorStop
        let name = displayName(group.name)

        switch group.category {
        case .tools:
            children = distinct(group.programs.map { programRow($0, in: group, cpu: cpu) })
            let count = group.programs.count
            detail = count > 1 ? "\(count) separate programs"
                : (group.programs.first?.whereItRuns.map { "in \($0)" } ?? "")
            stop = toolsStop(group)
        case .apps:
            children = group.parts.map { partRow($0, in: group, cpu: cpu) }
            detail = group.partsSummary ?? ""
            stop = appStop(group)
        case .system:
            children = group.parts.map { partRow($0, in: group, cpu: cpu) }
            detail = group.role ?? ""
            stop = .unavailable("Part of macOS — not something to quit from here.")
        }

        return MonitorRow(id: id, kind: .group, category: group.category, name: name, detail: detail,
                          memoryBytes: group.totalBytes, cpu: total(of: group.members, cpu),
                          processCount: group.members.count, pid: nil,
                          children: children, stop: stop, iconPID: group.lead.pid)
    }

    private static func partRow(_ part: CensusPart, in group: CensusGroup, cpu: [Int: Double]) -> MonitorRow {
        let leaves = part.members.map { processRow($0, in: group, cpu: cpu, locked: nil) }
        return MonitorRow(id: "group:\(group.id)/part:\(part.title)", kind: .part, category: group.category,
                          name: part.title, detail: "", memoryBytes: part.totalBytes,
                          cpu: total(of: part.members, cpu), processCount: part.members.count, pid: nil,
                          children: leaves, stop: .none, iconPID: nil)
    }

    private static func programRow(_ program: StopTarget, in group: CensusGroup, cpu: [Int: Double]) -> MonitorRow {
        let leaves = program.members.map {
            processRow($0, in: group, cpu: cpu, locked: program.lockedReason)
        }
        let stop: MonitorStop = program.lockedReason.map { .unavailable($0) }
            ?? (program.isStoppable
                ? .stopProgram(program)
                : .unavailable("This program belongs to another account or is not running."))
        // named for where it runs (what tells two of them apart), described by what it is
        return MonitorRow(id: "group:\(group.id)/\(program.id)", kind: .program, category: group.category,
                          name: program.whereItRuns ?? displayName(program.name),
                          detail: [program.whereItRuns == nil ? nil : displayName(program.name),
                                   program.lockedBy.map { "live \($0) session" }
                                    ?? (program.hostedSessions.isEmpty ? nil : "hosts live sessions")]
                              .compactMap { $0 }.joined(separator: " · "),
                          memoryBytes: program.totalBytes, cpu: total(of: program.members, cpu),
                          processCount: program.members.count, pid: program.identity?.pid ?? program.members.first?.pid,
                          children: leaves.count > 1 ? leaves : [], stop: stop,
                          iconPID: nil)
    }

    /// Two rows with one title in one group are told apart by their process ID.
    private static func distinct(_ rows: [MonitorRow]) -> [MonitorRow] {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.name, default: 0] += 1 }
        return rows.map { row in
            guard counts[row.name, default: 0] > 1, let pid = row.pid else { return row }
            var copy = row
            copy.name = "\(row.name) (process \(pid))"
            return copy
        }
    }

    private static func processRow(_ process: LiveProcess, in group: CensusGroup,
                                   cpu: [Int: Double], locked: String?) -> MonitorRow {
        let stop: MonitorStop
        switch group.category {
        case .tools:
            if let locked {
                stop = .unavailable(locked)
            } else if process.canQuit, let identity = ProcessIdentity.of(pid: process.pid) {
                stop = .stopProcess(process, identity)
            } else {
                stop = .unavailable("This process belongs to another account.")
            }
        case .apps:
            // a helper of an app is never stopped alone: quit the app
            stop = .none
        case .system:
            stop = .unavailable("Part of macOS — not something to stop from here.")
        }
        return MonitorRow(id: "process:\(process.pid)", kind: .process, category: group.category,
                          name: displayName(process.friendlyName), detail: "",
                          memoryBytes: process.memoryBytes, cpu: cpu[process.pid], processCount: 1,
                          pid: process.pid, children: [], stop: stop, iconPID: process.pid)
    }

    private static func appStop(_ group: CensusGroup) -> MonitorStop {
        guard case .app(let identities) = group.quit else { return .unavailable("Part of macOS.") }
        return .quitApp(name: group.name, identities: identities, processCount: group.members.count,
                        bytes: group.totalBytes, hosted: group.hostedSessions)
    }

    private static func toolsStop(_ group: CensusGroup) -> MonitorStop {
        guard case .tools = group.quit else {
            return .unavailable("These programs belong to another account.")
        }
        guard CodingAgentHosts.isAvailable else { return .unavailable(CodingAgentHosts.unavailableSentence) }
        if group.programs.allSatisfy({ $0.lockedBy != nil || !$0.hostedSessions.isEmpty }),
           let reason = group.programs.first?.lockedReason {
            return .unavailable(reason)
        }
        return .choosePrograms(group: displayName(group.name), programs: group.programs)
    }

    /// The ids from a top-level row down to the row for this process: what to open, then what to select.
    public static func path(toPID pid: Int, in rows: [MonitorRow]) -> [String]? {
        for row in rows {
            if row.pid == pid, row.kind == .process || row.children.isEmpty { return [row.id] }
            if let below = path(toPID: pid, in: row.children) { return [row.id] + below }
            if row.pid == pid { return [row.id] }
        }
        return nil
    }

    /// "Node.js process" is the glossary's name; a row says "Node.js".
    static func displayName(_ name: String) -> String {
        // a coding agent's own program is named for the product ("claude" → "Claude Code")
        if let agent = CodingAgentHosts.agent(forCommand: name) { return agent }
        return name == "Node.js process" ? "Node.js" : name
    }

    /// The same, for callers outside the module.
    public static func rowName(_ name: String) -> String { displayName(name) }

    private static func total(of processes: [LiveProcess], _ cpu: [Int: Double]) -> Double? {
        let readings = processes.compactMap { cpu[$0.pid] }
        return readings.isEmpty ? nil : readings.reduce(0, +)
    }

    // MARK: - updating in place

    /// A refresh: new values for rows that exist, in the order they already
    /// have. Nothing is re-sorted.
    ///
    /// Rows that appeared or went away are applied everywhere a person cannot
    /// see them — top-level rows and the children of a row that is closed. The
    /// children of a row that is OPEN keep the rows they had (with new values)
    /// until the next explicit refresh: adding or removing rows inside an open,
    /// live table makes AppKit log "reentrant operation in its NSTableView
    /// delegate" (measured with every group open: values-only ticks were clean,
    /// ticks that changed the rows were not). A process that ended therefore
    /// stays listed, at its last values, until Refresh Now or a new sort.
    public static func merge(_ old: [MonitorRow], with new: [MonitorRow],
                             open: Set<String> = []) -> [MonitorRow] {
        let fresh = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [MonitorRow] = []
        var kept = Set<String>()
        for row in old {
            guard var updated = fresh[row.id] else { continue }
            if open.contains(row.id) {
                let known = Set(row.children.map(\.id))
                updated.pendingNew = updated.children.filter { !known.contains($0.id) }.count
                updated.children = values(of: updated.children, into: row.children, open: open)
                updated.pendingEnded = updated.children.filter(\.isEnded).count
            } else {
                updated.children = merge(row.children, with: updated.children, open: open)
            }
            result.append(updated)
            kept.insert(row.id)
        }
        result.append(contentsOf: new.filter { !kept.contains($0.id) })
        return result
    }

    /// The rows that were there, with whatever fresh values exist for them; a
    /// row with none keeps its last values, and nothing new is added.
    private static func values(of fresh: [MonitorRow], into old: [MonitorRow], open: Set<String>) -> [MonitorRow] {
        let latest = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return old.map { row in
            guard var updated = latest[row.id] else {
                // it has ended: kept, at its last values, and not stoppable
                var ended = row
                ended.isEnded = true
                ended.cpu = nil
                ended.stop = .unavailable("This process has ended.")
                return ended
            }
            updated.children = values(of: updated.children, into: row.children, open: open)
            return updated
        }
    }

    // MARK: - sorting

    public enum SortKey: String, Sendable { case name, memory, cpu, pid }

    public struct Sort: Equatable, Sendable {
        public var key: SortKey
        public var ascending: Bool
        public init(_ key: SortKey, ascending: Bool) {
            self.key = key
            self.ascending = ascending
        }
        public static let biggestFirst = Sort(.memory, ascending: false)
    }

    /// Every level sorted, children within their parent.
    public static func sorted(_ rows: [MonitorRow], by sort: Sort) -> [MonitorRow] {
        func before(_ a: MonitorRow, _ b: MonitorRow) -> Bool {
            let order: Bool
            switch sort.key {
            case .name:
                let compared = a.name.localizedCaseInsensitiveCompare(b.name)
                if compared == .orderedSame { return a.id < b.id }
                order = compared == .orderedAscending
                return sort.ascending ? order : !order
            case .memory:
                if a.memoryBytes == b.memoryBytes { return a.id < b.id }
                order = a.memoryBytes < b.memoryBytes
            case .cpu:
                // rows with no reading go last whichever way it is sorted
                switch (a.cpu, b.cpu) {
                case (nil, nil): return a.id < b.id
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?):
                    if x == y { return a.id < b.id }
                    order = x < y
                }
            case .pid:
                switch (a.pid, b.pid) {
                case (nil, nil): return a.id < b.id
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?):
                    if x == y { return a.id < b.id }
                    order = x < y
                }
            }
            return sort.ascending ? order : !order
        }
        return rows.sorted(by: before).map { row in
            var copy = row
            copy.children = sorted(row.children, by: sort)
            return copy
        }
    }

    /// Every row's id in table order, depth first — what "the same order" means.
    public static func order(of rows: [MonitorRow]) -> [String] {
        rows.flatMap { [$0.id] + order(of: $0.children) }
    }

    // MARK: - categories

    /// What a category tab shows: how many groups and processes, and how much memory.
    public struct CategoryTotal: Sendable {
        public let category: CensusGroup.Category
        public let groups: Int
        public let processes: Int
        public let bytes: Int64
    }

    /// One total per category, in the order the tabs run: apps, tools, macOS.
    public static func categoryTotals(_ rows: [MonitorRow]) -> [CategoryTotal] {
        CensusGroup.Category.allCases.map { category in
            let mine = rows.filter { $0.category == category }
            return CategoryTotal(category: category, groups: mine.count,
                                 processes: mine.reduce(0) { $0 + $1.processCount },
                                 bytes: mine.reduce(Int64(0)) { $0 + $1.memoryBytes })
        }
    }

    // MARK: - filtering

    /// What the search and the scope leave in view: groups whose name, role or
    /// any process matches (a match deep inside keeps its ancestors).
    public static func filtered(_ rows: [MonitorRow], category: CensusGroup.Category?,
                                search: String) -> [MonitorRow] {
        let wanted = search.trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            (category == nil || row.category == category) && (wanted.isEmpty || row.matches(wanted))
        }
    }
}
