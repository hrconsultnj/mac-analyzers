import Foundation

/// One line of the Undo history: something a cleaner moved to the Trash, or a
/// dev server the guard stopped. A typed thing with a name a person recognises,
/// what happened in a sentence, when, who did it, and whether it can still be
/// brought back — never a path used as a title.
public struct UndoEntry: Identifiable, Sendable {

    public enum Scope: String, CaseIterable, Sendable {
        case trashed, stopped
    }

    public enum Source: Sendable {
        case trashed(TrashedItem)
        case stopped(GuardEvent)

        /// Where a trashed item came from.
        var trashedPath: String? { if case .trashed(let item) = self { item.originalPath } else { nil } }
    }

    public let id: String
    public let source: Source
    public let scope: Scope
    /// "node_modules", "Next.js dev server".
    public let title: String
    /// "Moved to the Trash by Temp & Agents · 262 MB" / "Stopped by the guard — was using 3.7 GB".
    public let outcome: String
    public let when: Date?
    /// Who did it: the screen's name for the cleaner ("Downloads"), or "Memory Guard".
    public let by: String
    /// What can be done now: restore, or why not. nil for a stopped server (copy command only).
    public let restore: Restore?
    public let sizeBytes: Int64
    /// Level 3: the cleanup run this was moved by ("temp-space|<banner>"), or the
    /// guard's stops of one day. Entries with the same run belong to one parent row.
    public let runID: String
    /// The app this went with, when the run was Unused Apps: the app's bundle path, from the `[APP]` line
    /// that opened the app's section of the run's block. The bundle itself and each of its files carry it.
    public var appPath: String? = nil
    /// What happened to this one, without the run's repeated details: its size.
    public var detail: String { sizeBytes > 0 ? ByteSize.format(sizeBytes) : "" }

    public enum Restore: Sendable, Equatable {
        case available
        case unavailable(reason: String)
    }

    public var isRestorable: Bool { restore == .available }
}

/// One cleanup run's moves, or one day of the guard's stops: the level-3 parent
/// row, with how many it holds and how much, that opens to its entries.
public struct UndoRun: Identifiable, Sendable {
    public let id: String
    public let by: String
    public let when: Date?
    public let entries: [UndoEntry]

    public var count: Int { entries.count }
    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }
    public var restorable: Int { entries.filter(\.isRestorable).count }
    public var isGuard: Bool { entries.first?.scope == .stopped }

    /// One row under the run. Entries with the same title fold into one
    /// ("Small temporary files · 3 items · 14 MB"), so a title never repeats in a group.
    public struct Child: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let outcome: String
        public let bytes: Int64
        public let entries: [UndoEntry]
        /// For an app: its bundle and each of its files, one row each; empty for everything else.
        public var files: [Child] = []
        public var isApp: Bool { !files.isEmpty }
        public var restorable: [UndoEntry] { entries.filter(\.isRestorable) }
    }

    public var children: [Child] {
        var order: [String] = []
        var byTitle: [String: [UndoEntry]] = [:]
        var apps: [String: [UndoEntry]] = [:]
        var appOrder: [String] = []
        for entry in entries {
            // an app's bundle and files go under the app, not among the run's other rows
            if let app = entry.appPath {
                if apps[app] == nil { appOrder.append(app) }
                apps[app, default: []].append(entry)
                continue
            }
            if byTitle[entry.title] == nil { order.append(entry.title) }
            byTitle[entry.title, default: []].append(entry)
        }
        let plain: [Child] = order.map { title in
            let group = byTitle[title]!
            let bytes = group.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if group.count == 1 {
                return Child(id: group[0].id, title: title, outcome: group[0].detail, bytes: bytes, entries: group)
            }
            return Child(id: "\(id)|\(title)", title: title,
                         outcome: "\(ActivitySummary.plural(group.count, "item", "items"))"
                             + (bytes > 0 ? " · \(ByteSize.format(bytes))" : ""),
                         bytes: bytes, entries: group)
        }
        return appOrder.map { app in appChild(path: app, entries: apps[app]!) } + plain
    }

    /// One app: its bundle first, then its files; the row says what it still holds.
    private func appChild(path: String, entries members: [UndoEntry]) -> Child {
        let name = Self.appName(path)
        let bundle = members.first { $0.source.trashedPath == path }
        let files = members.filter { $0.source.trashedPath != path }
        let bytes = members.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let size = bytes > 0 ? " · \(ByteSize.format(bytes))" : ""
        let count = ActivitySummary.plural(files.count, "file", "files")
        let said: String
        switch (bundle != nil, files.isEmpty) {
        case (true, true): said = "The app only\(size)"
        case (true, false): said = "The app and \(count)\(size)"
        // the app was put back (or its receipt is gone); what remains is its files
        case (false, _): said = "The app itself is back; \(count) still in the Trash\(size)"
        }
        let rows = ([bundle].compactMap { $0 } + files.sorted { $0.sizeBytes > $1.sizeBytes }).map {
            Child(id: $0.id, title: $0.title, outcome: $0.detail, bytes: $0.sizeBytes, entries: [$0])
        }
        return Child(id: "\(id)|app|\(path)", title: name, outcome: said, bytes: bytes, entries: members, files: rows)
    }

    /// "Foo" from "/Applications/Foo.app".
    static func appName(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    /// Said once on the run when nothing in it can be brought back.
    public var restoreNote: String? {
        guard !isGuard, restorable == 0, !entries.isEmpty else { return nil }
        let reasons = Set(entries.map { entry -> String in
            if case .unavailable(let reason)? = entry.restore { return reason }
            return ""
        })
        return reasons.count == 1
            ? reasons.first.map { $0.replacingOccurrences(of: "this can't", with: "these can't") }
            : "None of these can be restored from here."
    }

    /// "87 items · 1.6 GB · 3 can be restored", "2 servers".
    public var summary: String {
        if isGuard { return ActivitySummary.plural(count, "server", "servers") }
        var parts = [ActivitySummary.plural(count, "item", "items")]
        if totalBytes > 0 { parts.append(ByteSize.format(totalBytes)) }
        if restorable > 0 { parts.append("\(restorable) can be restored") }
        return parts.joined(separator: " · ")
    }
}

/// One day of the Undo history: its runs, newest first.
public struct UndoDay: Identifiable, Sendable {
    public let day: Date?
    public let runs: [UndoRun]
    public var entries: [UndoEntry] { runs.flatMap(\.entries) }
    public var id: String { day.map { String(Int($0.timeIntervalSince1970)) } ?? "undated" }

    public func title(now: Date, calendar: Calendar = .current) -> String {
        ActivityDay(day: day, rows: []).title(now: now, calendar: calendar)
    }

    /// "3 items moved to the Trash · 2.1 GB", "1 server stopped".
    public var summary: String {
        var parts: [String] = []
        let trashed = entries.filter { $0.scope == .trashed }
        let stopped = entries.filter { $0.scope == .stopped }
        if !trashed.isEmpty {
            parts.append("\(ActivitySummary.plural(trashed.count, "item", "items")) moved to the Trash")
            let bytes = trashed.reduce(Int64(0)) { $0 + $1.sizeBytes }
            if bytes > 0 { parts.append(ByteSize.format(bytes)) }
        }
        if !stopped.isEmpty { parts.append("\(ActivitySummary.plural(stopped.count, "server", "servers")) stopped") }
        return parts.joined(separator: " · ")
    }
}

public enum UndoHistory {

    /// Everything the Undo screen lists, newest first.
    public static func entries(now: Date = Date()) -> [UndoEntry] {
        let dates = receiptDates()
        let trashed = trashedEntries(UndoLedger.trashedItems(), dates: dates)
        let stopped: [UndoEntry] = GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, within: 90 * 86_400)
            .filter(\.isKill).map { event in
                var outcome = "Stopped by \(Names.Screen.memoryGuard)"
                if let size = event.residentText { outcome += " — was using \(size)" }
                if case .killed(let reason) = event.kind { outcome += " (\(reason))" }
                return UndoEntry(id: "stopped:" + event.id, source: .stopped(event), scope: .stopped,
                                 title: event.friendlyName, outcome: outcome, when: event.date,
                                 by: Names.Screen.memoryGuard, restore: nil, sizeBytes: 0,
                                 runID: "guard:" + String(Int(Calendar.current.startOfDay(for: event.date).timeIntervalSince1970)))
            }
        return (trashed + stopped).sorted { ($0.when ?? .distantPast) > ($1.when ?? .distantPast) }
    }

    /// Test support: the Trash entries of ONE receipt log, built exactly as the screen builds them.
    @_spi(TestSupport) public static func trashedEntries(ledger: URL, source: String, trash: URL) -> [UndoEntry] {
        let dates = receiptDates(runs: LogParser.runs(at: ledger), log: ledger.lastPathComponent)
        return trashedEntries(UndoLedger.trashedItems(in: ledger, source: source, trash: trash), dates: dates)
    }

    private static func trashedEntries(_ items: [TrashedItem], dates: [String: (date: Date, run: String, app: String?)]) -> [UndoEntry] {
        items.map { item in
            let by = Names.screen(forLedgerSource: item.source)
            let size = ByteSize.parse(item.sizeText) ?? 0
            let app = dates[item.originalPath]?.app
            return UndoEntry(
                id: "trashed:" + item.id, source: .trashed(item), scope: .trashed,
                title: title(for: item, appPath: app),
                outcome: "Moved to the Trash by \(by) · \(item.sizeText)" + diskNote(item)
                    + (item.restorability == .trashCopyGone ? " — the Trash has since been emptied" : ""),
                when: dates[item.originalPath]?.date, by: by,
                restore: restore(for: item.restorability), sizeBytes: size,
                runID: dates[item.originalPath]?.run ?? "undated:" + item.ledger.lastPathComponent,
                appPath: app)
        }
    }

    public static func days(_ entries: [UndoEntry], calendar: Calendar = .current) -> [UndoDay] {
        var byDay: [Date?: [UndoEntry]] = [:]
        for entry in entries { byDay[entry.when.map { calendar.startOfDay(for: $0) }, default: []].append(entry) }
        return byDay.map { day, dayEntries in
            let byRun = Dictionary(grouping: dayEntries, by: \.runID)
            let runs = byRun.map { id, members in
                UndoRun(id: id, by: members[0].by, when: members.compactMap(\.when).max(),
                        entries: members.sorted { $0.sizeBytes > $1.sizeBytes })
            }.sorted {
                if ($0.restorable > 0) != ($1.restorable > 0) { return $0.restorable > 0 }
                return ($0.when ?? .distantPast) > ($1.when ?? .distantPast)
            }
            return UndoDay(day: day, runs: runs)
        }.sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
    }

    /// A name a person would use for what was moved: a family token reads as
    /// "<name> files", a path as its last component.
    static func title(for item: TrashedItem, appPath: String? = nil) -> String {
        // an app's bundle is the app; a recording is its file's own name
        if let appPath, item.originalPath == appPath { return UndoRun.appName(appPath) }
        if item.source == "Old Recordings" { return item.basename }
        // everything else is named by the one function the Storage screens use
        guard item.isGroup else { return StorageNaming.name(forPath: item.originalPath).title }
        // "<dir>/<family>*": the siblings that went to the Trash together
        var family = item.basename.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        if family.isEmpty { family = "Temporary" }
        // a bundle id or file prefix stays as it is written; a plain word is capitalised
        let name = family.contains(".") ? family : family.prefix(1).uppercased() + family.dropFirst()
        let title = name + (family.lowercased().hasSuffix("files") ? "" : " files")
        // "(small files)" is the same in every folder, and a folder like "T" means
        // nothing to a person: one name, folded into one row per run
        return family.lowercased() == "small files" ? "Small temporary files" : title
    }

    /// " · on Backup" for an item that is in another disk's own Trash.
    static func diskNote(_ item: TrashedItem) -> String {
        let parts = (item.trashPath ?? "").split(separator: "/")
        guard parts.count > 2, parts[0] == "Volumes" else { return "" }
        return " · on \(parts[1])"
    }

    static func restore(for state: TrashedItem.Restorability) -> UndoEntry.Restore {
        switch state {
        case .restorable:
            return .available
        case .trashCopyGone:
            return .unavailable(reason: "The Trash has been emptied, so this can't be brought back.")
        case .destinationUnknown:
            return .unavailable(reason: "It was moved before the app recorded where it came from. Drag it back from the Trash yourself.")
        case .pathOccupied:
            return .unavailable(reason: "Something new is at the original location. Restore it from the Trash yourself.")
        default:
            let why = UndoLedger.reason(state)
            return .unavailable(reason: "It can't be restored: " + why.prefix(1).uppercased() + why.dropFirst())
        }
    }

    /// When each trashed path was moved: the start of the run whose receipt
    /// lists it, newest run winning.
    static func receiptDates() -> [String: (date: Date, run: String, app: String?)] {
        var dates: [String: (date: Date, run: String, app: String?)] = [:]
        for log in [EngineLog.janitor, .tempSpace, .cleanupApps, .cleanupRecordings] {
            dates.merge(receiptDates(runs: LogParser.allRuns(for: log), log: log.rawValue)) { _, newer in newer }
        }
        return dates
    }

    /// The receipts of one log's runs: when each path was moved, by which run, and for Unused Apps with which app.
    static func receiptDates(runs: [LogRun], log: String) -> [String: (date: Date, run: String, app: String?)] {
        var dates: [String: (date: Date, run: String, app: String?)] = [:]
        for run in runs.reversed() {   // oldest first, so the newest wins
            guard let date = TrendTotals.runDate(run.header) else { continue }
            // Unused Apps writes `[APP] <bundle path>` and then, for that app, the receipt of the bundle and one
            // for each of its files; the next `[APP]` opens the next app. That order is what ties a file to its app.
            var app: String?
            for line in run.lines {
                if line.hasPrefix("[APP]") {
                    let path = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    app = path.hasPrefix("/") ? path : nil
                    continue
                }
                guard line.hasPrefix("[TRASHED]"), let range = line.range(of: "  ") else { continue }
                let rest = String(line[range.upperBound...])
                let original = ReceiptIdentity.split(rest).text.components(separatedBy: "  ->  ")[0].trimmingCharacters(in: .whitespaces)
                if original.hasPrefix("/") { dates[original] = (date, log + "|" + run.header, app) }
            }
        }
        return dates
    }
}
