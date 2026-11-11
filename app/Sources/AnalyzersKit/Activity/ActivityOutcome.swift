import Foundation

/// What a finished run did, as a readable list: what was freed, found or
/// skipped, one typed row each. Built from the task's own parser, never from
/// the raw lines (those stay behind "Show raw output").
public struct ActivityOutcome: Sendable {

    public enum Tone: Sendable {
        /// Something was done.
        case done
        /// Something was found and is still there.
        case found
        /// Something worth knowing happened (a guard alert).
        case alert
        /// Left alone on purpose.
        case skipped
        case failed
        case info
    }

    public struct Item: Identifiable, Sendable {
        public let id: Int
        public let title: String
        public let detail: String?
        /// A size, or a time.
        public let trailing: String?
        /// The real-world thing the row belongs to (a project), where the parser
        /// gives it as data; nil otherwise. Never recovered by splitting `title`.
        public let group: String?
        /// The row's size in bytes, where it has one (for totals and ordering).
        public let bytes: Int64?
        public init(id: Int, title: String, detail: String? = nil, trailing: String? = nil,
                    group: String? = nil, bytes: Int64? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.trailing = trailing
            self.group = group
            self.bytes = bytes
        }
    }

    public struct Section: Identifiable, Sendable {
        public let id: Int
        public let title: String
        public let tone: Tone
        public let items: [Item]
        /// Items beyond `ActivityOutcome.itemLimit`, not shown.
        public let hidden: Int
    }

    public let sections: [Section]
    public init(sections: [Section]) { self.sections = sections }
    public var isEmpty: Bool { sections.allSatisfy { $0.items.isEmpty } }

    /// A janitor preview can hold thousands of rows; the list shows the
    /// biggest and says how many more there are.
    public static let itemLimit = 200

    // MARK: - building

    private struct Builder {
        var sections: [Section] = []
        mutating func add(_ title: String, _ tone: Tone, _ items: [Item]) {
            guard !items.isEmpty else { return }
            let shown = Array(items.prefix(ActivityOutcome.itemLimit))
            sections.append(Section(id: sections.count, title: title, tone: tone, items: shown,
                                    hidden: items.count - shown.count))
        }
    }

    public static func make(_ parsed: JobOutcome.Parsed, run: LogRun?, log: EngineLog?) -> ActivityOutcome {
        var b = Builder()
        switch parsed {
        case .reap(let reap):
            func rows(_ items: [ReapItem]) -> [Item] {
                items.enumerated().map { index, item in
                    Item(id: index, title: item.friendlyName,
                         detail: item.pid.map { "Process \($0)" },
                         trailing: item.mb.map { "\($0) MB" })
                }
            }
            let all = reap.allItems
            b.add("Closed", .done, rows(all.filter { $0.status == .killed || $0.status == .quit }))
            b.add("Would be closed", .found, rows(all.filter { $0.status == .dry }))
            b.add("Left running", .skipped, rows(all.filter { [.exempt, .skip, .reported].contains($0.status) }))

        case .storage(let storage):
            func rows(_ items: [StoragePathItem]) -> [Item] {
                items.sorted { $0.sizeBytes > $1.sizeBytes }.enumerated().map { index, item in
                    Item(id: index, title: item.cacheKind, detail: Self.shortPath(item.path),
                         trailing: ByteSize.format(item.sizeBytes), group: item.project, bytes: item.sizeBytes)
                }
            }
            b.add("Freed", .done, rows(storage.items.filter { $0.status == .deleted }))
            b.add("Moved to the Trash", .done, rows(storage.items.filter { $0.status == .trashed }))
            b.add("Found", .found, rows(storage.items.filter { $0.status == .dry }))
            b.add("Couldn't remove", .failed, rows(storage.items.filter { $0.status == .failed }))
            if let tm = storage.tmNote { b.add("Time Machine", .info, [Item(id: 0, title: tm)]) }

        case .temp(let temp):
            func rows(_ items: [TempItem]) -> [Item] {
                items.sorted { $0.sizeBytes > $1.sizeBytes }.enumerated().map { index, item in
                    Item(id: index, title: item.displayName, detail: Self.shortPath(item.parentPath),
                         trailing: ByteSize.format(item.sizeBytes), bytes: item.sizeBytes)
                }
            }
            b.add("Cleared", .done, rows(temp.actedItems))
            b.add("Ready to clear", .found, rows(temp.readyItems))
            b.add("Couldn't clear", .failed, rows(temp.items.filter { $0.status == .failed }))
            let ejected = temp.mounts.filter { $0.status == .ejected }
            b.add("Disk images ejected", .done, ejected.enumerated().map {
                Item(id: $0.offset, title: ($0.element.mountPoint as NSString).lastPathComponent)
            })

        case .spotlight(let spot):
            func rows(_ items: [SpotlightExposureItem]) -> [Item] {
                items.sorted { $0.sizeBytes > $1.sizeBytes }.enumerated().map { index, item in
                    Item(id: index, title: (item.path as NSString).lastPathComponent,
                         detail: Self.shortPath(item.path), trailing: ByteSize.format(item.sizeBytes),
                         group: item.project, bytes: item.sizeBytes)
                }
            }
            b.add("Fenced", .done, rows(spot.fencedItems))
            b.add("Not fenced yet", .found, rows(spot.dryItems))
            if let verdict = spot.verdictDetail {
                b.add("Indexing", .info, [Item(id: 0, title: spot.verdict.rawValue.capitalized, detail: verdict)])
            }

        case .loginItems(let login):
            func rows(_ entries: [LoginItemEntry]) -> [Item] {
                entries.enumerated().map { Item(id: $0.offset, title: $0.element.displayName,
                                                detail: $0.element.note ?? $0.element.targetPath) }
            }
            let all = login.allEntries
            b.add("Removed", .done, rows(all.filter { $0.verdict == .removed }))
            b.add("Leftover", .found, rows(all.filter { $0.verdict == .orphan || $0.verdict == .orphanSudo }))
            b.add("Worth a look", .skipped, rows(all.filter { $0.verdict == .leftover }))

        case .none:
            guard let run, let log else { break }
            addEvents(&b, run: run, log: log)
        }
        return ActivityOutcome(sections: b.sections)
    }

    /// The event logs: a day of guard events, startup changes, a crisis report.
    private static func addEvents(_ b: inout Builder, run: LogRun, log: EngineLog) {
        switch log {
        case .guardLog:
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let events = run.lines.compactMap(GuardLogParser.parseLine).sorted { $0.date > $1.date }
            /// Repeats of the same thing on the same app collapse into one row with a count.
            func items(_ matching: (GuardEvent) -> Bool) -> [Item] {
                var order: [String] = []
                var groups: [String: [GuardEvent]] = [:]
                for event in events.filter(matching) {
                    let key = eventTitle(event)
                    if groups[key] == nil { order.append(key) }
                    groups[key, default: []].append(event)
                }
                return order.enumerated().map { index, title in
                    let group = groups[title] ?? []
                    let newest = group.first?.date ?? Date()
                    let oldest = group.last?.date ?? newest
                    let detail = group.count == 1
                        ? group.first?.residentText.map { "Using \($0)" }
                        : "\(group.count) times, from \(formatter.string(from: oldest)) to \(formatter.string(from: newest))"
                    return Item(id: index, title: title, detail: detail, trailing: formatter.string(from: newest))
                }
            }
            b.add("Stopped", .done, items { $0.isKill })
            b.add("Alerts", .alert, items { !$0.isKill })

        case .persistence:
            let added = run.lines.filter { $0.contains("NEW persistence item") }
            b.add("Added to startup", .found, added.enumerated().map { index, line in
                let path = line.components(separatedBy: "NEW persistence item:").last?
                    .trimmingCharacters(in: .whitespaces) ?? line
                return Item(id: index, title: (path as NSString).lastPathComponent, detail: Self.shortPath(path))
            })

        case .forensics:
            let snapshot = ForensicsParser.parse(text: run.lines.joined(separator: "\n"))
            var status: [Item] = []
            if let phys = snapshot.physMemLine { status.append(Item(id: 0, title: "Memory", detail: phys)) }
            if let swap = snapshot.swapLine { status.append(Item(id: 1, title: "Swap", detail: swap)) }
            b.add("Where things stood", .info, status)
            b.add("Using the most memory", .found, snapshot.processes.prefix(10).enumerated().map {
                Item(id: $0.offset, title: $0.element.friendlyName, detail: "Process \($0.element.pid)",
                     trailing: $0.element.rssText)
            })

        default:
            break
        }
    }

    /// "~/Library/Caches/Google" rather than the full home path.
    static func shortPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// A process as a person knows it: the glossary's name, else the program's own.
    private static func appName(_ event: GuardEvent) -> String {
        ProcessGlossary.friendlyName(for: event.processName)
            ?? (event.processName as NSString).lastPathComponent
    }

    private static func eventTitle(_ event: GuardEvent) -> String {
        let name = appName(event)
        switch event.kind {
        case .killed: return "Stopped \(name)"
        case .spike(let grew): return "\(name) grew by \(grew) MB"
        case .cpuHog(let pct, _): return "\(name) used \(pct)% of a core"
        case .capExceeded: return "Memory limit passed"
        case .pressureWarning: return "Memory pressure warning"
        case .pressureCritical: return "Memory pressure critical"
        case .forensics: return "Crisis report saved"
        case .warning: return event.processName
        }
    }
}
