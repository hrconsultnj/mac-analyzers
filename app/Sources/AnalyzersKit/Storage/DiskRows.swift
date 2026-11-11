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

    public var id: String { kind.rawValue }
    public var title: String { Names.job(kind) }
}

/// The Disk screen's rows: one per storage task, each from the newest
/// preview in that task's own log.
public enum StorageTasks {

    public static func load() -> [StorageTask] {
        [caches(), downloads(), temp(), spotlight()]
    }

    static func caches() -> StorageTask {
        guard let run = StorageRunReader.run(in: AnalyzersPaths.storageAutoCleanLog, header: nil) else {
            return StorageTask(kind: .storageClean, reclaimableBytes: nil, measuredAt: nil,
                               detail: "No preview yet. Check to see what could go.")
        }
        let parsed = StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
        let review = CacheReview.build(from: parsed, roots: CacheReview.roots(in: run.lines), modified: { _ in nil })
        let count = review.candidates.count
        return StorageTask(kind: .storageClean, reclaimableBytes: review.totalBytes,
                           measuredAt: RunDate.date(of: run.header),
                           detail: count == 0 ? "Nothing to clean."
                                              : "\(count) folder\(count == 1 ? "" : "s") in \(review.projects.count) project\(review.projects.count == 1 ? "" : "s").")
    }

    static func downloads() -> StorageTask {
        guard let run = StorageRunReader.run(in: AnalyzersPaths.janitorLog, header: nil) else {
            return StorageTask(kind: .janitor, reclaimableBytes: nil, measuredAt: nil,
                               detail: "No preview yet. Check to see what could go.")
        }
        let review = DownloadReview.build(lines: run.lines, info: { _ in (nil, false) })
        let count = review.candidates.count
        return StorageTask(kind: .janitor, reclaimableBytes: review.totalBytes,
                           measuredAt: RunDate.date(of: run.header),
                           detail: count == 0 ? "Nothing old enough to move."
                                              : "\(count) old item\(count == 1 ? "" : "s"), moved to the Trash.")
    }

    static func temp() -> StorageTask {
        guard let run = StorageRunReader.run(in: AnalyzersPaths.tempCleanLog, header: nil) else {
            return StorageTask(kind: .tempClean, reclaimableBytes: nil, measuredAt: nil,
                               detail: "No audit yet. Check to see what could go.")
        }
        let review = TempReview.build(from: TempCleanParser.parse(runHeader: run.header, lines: run.lines))
        let count = review.ready.count
        return StorageTask(kind: .tempClean, reclaimableBytes: review.readyBytes,
                           measuredAt: RunDate.date(of: run.header),
                           detail: count == 0 ? "Nothing is ready to clear."
                                              : "\(count) item\(count == 1 ? "" : "s") ready to clear.")
    }

    static func spotlight() -> StorageTask {
        guard let run = StorageRunReader.run(in: AnalyzersPaths.spotlightAuditLog, header: nil) else {
            return StorageTask(kind: .spotlight, reclaimableBytes: nil, measuredAt: nil,
                               detail: "No audit yet. Check to see what Spotlight indexes.")
        }
        let review = SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: run.header, lines: run.lines),
                                           current: { _ in nil })
        let count = review.unfenced.count
        return StorageTask(kind: .spotlight, reclaimableBytes: nil, measuredAt: RunDate.date(of: run.header),
                           detail: count == 0 ? "Every developer folder is fenced."
                                              : "\(count) developer folder\(count == 1 ? "" : "s") still indexed.")
    }
}
