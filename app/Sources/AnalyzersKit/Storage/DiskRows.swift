import Foundation

/// One storage task on the Disk screen: what it could free, from which look,
/// and where it lives.
public struct StorageTask: Identifiable, Sendable {
    public let kind: JobKind
    /// Bytes a cleanup would free, as of the latest preview; nil when there has
    /// been no preview yet.
    public let reclaimableBytes: Int64?
    public let measuredAt: Date?
    /// A sentence on what the figure is made of.
    public let detail: String

    public init(kind: JobKind, reclaimableBytes: Int64?, measuredAt: Date?, detail: String) {
        self.kind = kind; self.reclaimableBytes = reclaimableBytes; self.measuredAt = measuredAt; self.detail = detail
    }

    public var id: String { kind.rawValue }
    public var title: String { Names.job(kind) }
}

/// The Disk screen's rows: one per storage task, each from the newest
/// preview in that task's own log, read whole.
public enum StorageTasks {

    public static func load() -> [StorageTask] {
        [caches(), downloads(), temp(), spotlight()]
    }

    private static func none(_ kind: JobKind, _ detail: String) -> StorageTask {
        StorageTask(kind: kind, reclaimableBytes: nil, measuredAt: nil, detail: detail)
    }

    private static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    static func caches() -> StorageTask {
        guard let run = StorageLog.newestPreview(of: .storageClean) else {
            return none(.storageClean, "No preview yet. Preview to see what could go.")
        }
        let review = CacheReview.build(lines: run.lines, banner: run.banner, modified: { _ in nil })
        let sized = review.rows.rows.filter { $0.bytes != nil }
        let inProjects = review.rows.rows(in: CacheCategory.projects).filter { $0.bytes != nil }
        let projects = Set(inProjects.compactMap(\.group)).count
        let appCaches = review.rows.rows(in: CacheCategory.appCaches).filter { $0.bytes != nil }.count
        let tools = review.rows.rows(in: CacheCategory.developerTools).filter { $0.bytes != nil }.count
        var parts: [String] = []
        if !inProjects.isEmpty { parts.append("\(plural(inProjects.count, "folder")) in \(plural(projects, "project"))") }
        if appCaches > 0 { parts.append(plural(appCaches, "app cache")) }
        if tools > 0 { parts.append(plural(tools, "developer tool cache")) }
        return StorageTask(kind: .storageClean, reclaimableBytes: review.rows.totalBytes,
                           measuredAt: RunDate.date(of: run.banner),
                           detail: sized.isEmpty ? "Nothing to clean."
                                                 : "\(review.mode.title) preview: " + ListFormatter.localizedString(byJoining: parts) + ".")
    }

    static func downloads() -> StorageTask {
        guard let run = StorageLog.newestPreview(of: .janitor) else {
            return none(.janitor, "No preview yet. Preview to see what could go.")
        }
        let review = DownloadReview.build(lines: run.lines, info: { _ in (nil, false) })
        let count = review.rows.choosable.count
        return StorageTask(kind: .janitor, reclaimableBytes: review.rows.choosableBytes,
                           measuredAt: RunDate.date(of: run.banner),
                           detail: count == 0 ? "Nothing old enough to move."
                                              : "\(plural(count, "old item")) can go to the Trash.")
    }

    static func temp() -> StorageTask {
        guard let run = StorageLog.newestPreview(of: .tempClean) else {
            return none(.tempClean, "No audit yet. Preview to see what could go.")
        }
        let review = TempReview.build(from: TempCleanParser.parse(runHeader: run.banner, lines: run.lines))
        let count = review.ready.count
        return StorageTask(kind: .tempClean, reclaimableBytes: review.readyBytes,
                           measuredAt: RunDate.date(of: run.banner),
                           detail: count == 0 ? "Nothing is ready to clear." : "\(plural(count, "item")) ready to clear.")
    }

    static func spotlight() -> StorageTask {
        guard let run = StorageLog.newestPreview(of: .spotlight) else {
            return none(.spotlight, "No audit yet. Preview to see what Spotlight indexes.")
        }
        let review = SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: run.banner, lines: run.lines),
                                           current: { _ in nil })
        let count = review.unfenced.count
        return StorageTask(kind: .spotlight, reclaimableBytes: nil, measuredAt: RunDate.date(of: run.banner),
                           detail: count == 0 ? "Every developer folder is fenced."
                                              : "\(plural(count, "developer folder")) still indexed.")
    }
}
