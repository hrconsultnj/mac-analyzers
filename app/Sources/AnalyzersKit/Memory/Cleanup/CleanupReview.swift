import Foundation

/// The memory cleanup's preview, read as a review: the programs it would
/// close (tickable), the ones it found and left alone, the helpers it keeps
/// because a live session owns them, and the apps on the "also quit" list.
///
/// Built from `ReapRun`, which the kernel already parses for a finished
/// preview, so what is reviewed is exactly what the engine printed.
///
///   CleanupCandidate.swift   one row
///   CleanupReview.swift      this file: the rows of a run, selection, the approved set
///   CleanupReview+Words.swift  the engine's findings in plain words
public struct CleanupReview: Sendable {

    public let candidates: [CleanupCandidate]
    /// "Protected sessions are exempt" — the engine's note, when it printed one.
    public let protectedNote: String?
    public let isPreview: Bool

    public init(run: ReapRun) {
        isPreview = run.dryRun
        protectedNote = run.exemptNote.flatMap { $0.isEmpty ? nil : $0 }
        var rows: [CleanupCandidate] = []
        var index = 0
        for group in run.groups {
            let groupName = Self.groupName(forTitle: group.title)
            for item in group.items {
                if let candidate = Self.candidate(from: item, group: groupName, ordinal: index, title: group.title) {
                    rows.append(candidate)
                }
                index += 1
            }
            for aggregate in group.aggregates {
                let name = Self.keptName(aggregate.label)
                rows.append(CleanupCandidate(
                    id: "kept-\(index)", pid: nil, name: name,
                    detail: nil, reason: "Belongs to a live session, so it is not closed.",
                    group: groupName, memoryMB: aggregate.totalMB, count: aggregate.count, state: .kept,
                    category: .liveSessions, groupName: "Live sessions", identity: nil))
                index += 1
            }
        }
        candidates = rows
    }

    // MARK: - what can be ticked

    public var selectable: [CleanupCandidate] { candidates.filter(\.isSelectable) }

    /// What the engine will ask to quit by name, whatever is ticked.
    public var appQuits: [CleanupCandidate] { candidates.filter { $0.state == .willBeAskedToQuit } }

    /// Every key the review offered: one pid per tickable row.
    public var approvableKeys: [String] { selectable.compactMap(\.approvalKey) }

    /// What the person left ticked, for `JobStore.apply(from:approved:)`.
    /// Nothing unticked sends no list (the engine runs as it always did);
    /// unticking sends the ticked pids, and an engine that finds more than was
    /// reviewed can only close fewer. When there is nothing to tick at all — a
    /// run whose only action is asking apps to quit — an explicit EMPTY list is
    /// sent, so an apply can never close a process nobody reviewed.
    ///
    /// A row whose pid is no longer the program the review showed (it ended, or
    /// the system gave the pid to another program) counts as unticked, whatever
    /// the person did: the engine has its own check, and this is the app's.
    public func approvedSet(deselected: Set<String>) -> ApprovedSet {
        guard !approvableKeys.isEmpty else {
            return ApprovedSet(approvable: ["none"], deselected: ["none"])
        }
        let changed = Set(changedSinceReview().compactMap(\.approvalKey))
        return ApprovedSet(approvable: approvableKeys, deselected: deselected.union(changed))
    }

    /// What may be ticked in the review: a program the preview found that is still the program it
    /// found, and that is worth closing. A program using no memory is shown folded away and is never
    /// chosen (closing it frees nothing); one whose pid is no longer the reviewed program, or that is
    /// left alone, cannot be ticked either. The review table, its count and what Apply sends all use this.
    public func isTickable(_ candidate: CleanupCandidate, changed: Set<String>) -> Bool {
        guard candidate.isSelectable, !candidate.isEmpty else { return false }
        return !changed.contains(candidate.approvalKey ?? "")
    }

    /// The keys of tickable rows that are no longer the program that was reviewed.
    public func changedKeys() -> Set<String> {
        Set(changedSinceReview().compactMap(\.approvalKey))
    }

    /// What Apply sends: exactly the ticked rows, minus any whose pid is no longer the reviewed program.
    /// Rows that cannot be ticked (left alone, kept, folded away as nothing) are never in it, whatever
    /// "Select All" did. Nothing to send at all is an explicit empty list, so an apply can never close a
    /// process nobody reviewed.
    public func approvedSet(ticked: Set<String>) -> ApprovedSet {
        guard !approvableKeys.isEmpty else {
            return ApprovedSet(approvable: ["none"], deselected: ["none"])
        }
        let changed = changedKeys()
        let wanted = Set(approvableKeys).intersection(ticked).subtracting(changed)
        if wanted.isEmpty { return ApprovedSet(approvable: ["none"], deselected: ["none"]) }
        return ApprovedSet(approvable: approvableKeys, deselected: Set(approvableKeys).subtracting(wanted))
    }

    /// Tickable rows whose pid is not the program that was reviewed any more.
    public func changedSinceReview() -> [CleanupCandidate] {
        // a row with no identity is one whose process was already gone when the
        // review was read: it counts as changed, never as unchanged
        selectable.filter { candidate in
            guard let identity = candidate.identity else { return true }
            return !identity.isStillRunning
        }
    }

    // MARK: - levels

    public struct Group: Identifiable, Sendable {
        public let name: String
        public let rows: [CleanupCandidate]
        public var id: String { name }
        public var count: Int { rows.reduce(0) { $0 + $1.count } }
        public var bytes: Int64 { rows.reduce(0) { $0 + $1.memoryBytes } }
    }

    public struct CategoryTotal: Identifiable, Sendable {
        public let category: CleanupCandidate.Category
        public let groups: [Group]
        /// Rows that give back nothing, folded into one closed row.
        public let empty: [CleanupCandidate]
        public var id: String { category.rawValue }
        public var count: Int { groups.reduce(0) { $0 + $1.count } + empty.count }
        public var bytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    }

    /// The review as the screen shows it: a tab per kind of thing that has
    /// anything in it, rows grouped by the app, project or session they belong
    /// to (biggest first), and rows that are nothing folded away.
    public func categories() -> [CategoryTotal] {
        CleanupCandidate.Category.allCases.compactMap { category in
            let mine = candidates.filter { $0.category == category }
            guard !mine.isEmpty else { return nil }
            let live = mine.filter { !$0.isEmpty }
            let grouped = Dictionary(grouping: live, by: \.groupName)
            let groups = grouped.map { name, rows in Group(name: name, rows: Self.distinct(rows)) }
                .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
            return CategoryTotal(category: category, groups: groups, empty: mine.filter(\.isEmpty))
        }
    }

    /// Biggest first; two rows with one title are told apart by their process ID.
    private static func distinct(_ rows: [CleanupCandidate]) -> [CleanupCandidate] {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.name, default: 0] += 1 }
        return rows
            .map { row in
                guard counts[row.name, default: 0] > 1, let pid = row.pid else { return row }
                return row.renamed("\(row.name) (process \(pid))")
            }
            .sorted { $0.memoryBytes != $1.memoryBytes ? $0.memoryBytes > $1.memoryBytes : $0.id < $1.id }
    }

    public func selectedCount(deselected: Set<String>) -> Int {
        approvableKeys.filter { !deselected.contains($0) }.count
    }

    public func selectedBytes(deselected: Set<String>) -> Int64 {
        selectable.filter { !deselected.contains($0.approvalKey ?? "") }
            .reduce(0) { $0 + $1.memoryBytes }
    }

    /// Whether Apply has anything to do.
    public func hasAction(deselected: Set<String>) -> Bool {
        selectedCount(deselected: deselected) > 0 || !appQuits.isEmpty
    }
}
