import Foundation

/// Whether Spotlight is kept out of a folder.
public enum FenceState: String, Sendable {
    case fenced, notFenced

    public var title: String { self == .fenced ? Names.Fence.fenced : Names.Fence.notFenced }
}

/// One developer folder Spotlight would index, and whether it is fenced.
public struct SpotlightFolder: Identifiable, Hashable, Sendable {
    public let path: String
    public let project: String
    public let kind: CacheKind
    public let sizeBytes: Int64
    public var state: FenceState

    public var id: String { path }
    public var folderName: String { (path as NSString).lastPathComponent }
    public var shortPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    /// The marker file whose presence keeps Spotlight out.
    public var marker: String { (path as NSString).appendingPathComponent(".metadata_never_index") }

    /// Why it matters, in a sentence a person can weigh.
    public var why: String {
        switch state {
        case .fenced: "Spotlight skips it, so searches stay fast and fans stay quiet."
        case .notFenced:
            "Spotlight indexes every file in it. Fencing it keeps the index small; nothing is moved or deleted."
        }
    }
}

/// Spotlight's own state and the folders it would index.
public struct SpotlightReview: Sendable {
    /// "Indexing is on."
    public let status: String
    public let verdict: SpotlightAuditRun.Verdict
    /// What the verdict means, in a sentence.
    public let verdictSentence: String
    public let folders: [SpotlightFolder]
    public let unfencedBulkBytes: Int64?
    public let deepCheckCommand: String?
    public let rebuildCommand: String?

    public var unfenced: [SpotlightFolder] { folders.filter { $0.state == .notFenced } }
    public var fenced: [SpotlightFolder] { folders.filter { $0.state == .fenced } }

    /// `current` says whether a folder is fenced RIGHT NOW (the marker file),
    /// or nil when the folder is gone and the log's word is all there is.
    public static func build(from run: SpotlightAuditRun,
                             current: (String) -> FenceState? = { SpotlightReview.markerState(of: $0) })
        -> SpotlightReview {
        let folders = run.exposureItems.map { item in
            SpotlightFolder(path: item.path, project: item.project, kind: CacheKind(folder: item.cacheKind),
                            sizeBytes: item.sizeBytes,
                            state: current(item.path) ?? (item.status == .fenced ? .fenced : .notFenced))
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        let indexing = run.indexingLine?.lowercased().contains("disabled") == true ? "Indexing is off." : "Indexing is on."
        let sentence: String
        switch run.verdict {
        case .progressing: sentence = "Spotlight is busy indexing right now."
        case .idleOrComplete: sentence = "Spotlight is idle: indexing is finished or waiting."
        case .notRunning: sentence = "Spotlight isn't indexing at the moment."
        case .unknown: sentence = "The audit couldn't tell whether indexing is stuck."
        }
        return SpotlightReview(status: indexing, verdict: run.verdict, verdictSentence: sentence, folders: folders,
                               unfencedBulkBytes: run.unfencedBulkBytes, deepCheckCommand: run.deepCheckCommand,
                               rebuildCommand: run.rebuildCommand)
    }
}

extension SpotlightReview {
    /// The marker file decides, because a fence can be placed or lifted after
    /// the audit ran. nil when the folder no longer exists.
    public static func markerState(of path: String) -> FenceState? {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        let marker = (path as NSString).appendingPathComponent(".metadata_never_index")
        return fm.fileExists(atPath: marker) ? .fenced : .notFenced
    }
}
