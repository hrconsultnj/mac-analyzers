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

    public init(path: String, project: String, kind: CacheKind, sizeBytes: Int64, state: FenceState, title: String) {
        self.path = path; self.project = project; self.kind = kind; self.sizeBytes = sizeBytes
        self.state = state; self.title = title
    }

    public var id: String { path }
    /// "apps/mobile · Node.js Packages": where in the project, and what it is.
    public let title: String
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

/// Spotlight has one kind of thing (folders), so its screen has no tabs.
public enum SpotlightCategory: String, StorageCategory {
    case folders
    public var title: String { Names.Screen.spotlight }
    public var symbol: String { "magnifyingglass" }
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
    /// What section 1 of the check said besides on or off: Spotlight's helper processes, and a recent macOS update.
    public let statusDetails: [String]

    /// The folders as the rows Storage screens share: grouped by project, each saying whether it
    /// is fenced (a run's results read the same way).
    public var rows: StorageRows {
        StorageRows(folders.map {
            StorageRow(id: $0.path, category: SpotlightCategory.folders.rawValue, group: $0.project, title: $0.title,
                       detail: "\($0.state.title) · \(StorageLog.short($0.path))", bytes: $0.sizeBytes, iconPath: $0.path)
        })
    }

    public var unfenced: [SpotlightFolder] { folders.filter { $0.state == .notFenced } }
    public var fenced: [SpotlightFolder] { folders.filter { $0.state == .fenced } }

    /// `current` says whether a folder is fenced RIGHT NOW (the marker file),
    /// or nil when the folder is gone and the log's word is all there is.
    public static func build(from run: SpotlightAuditRun,
                             current: (String) -> FenceState? = { SpotlightReview.markerState(of: $0) })
        -> SpotlightReview {
        let roots = run.exposureRoots.map { $0.split(separator: " ").map(String.init) } ?? []
        let folders = run.exposureItems.map { item -> SpotlightFolder in
            let kind = CacheKind(folder: item.cacheKind)
            let project = CacheReview.projectPath(of: item.path, roots: roots)
            let relative = item.path.hasPrefix(project + "/") ? String(item.path.dropFirst(project.count + 1)) : item.cacheKind
            let folder = (relative as NSString).deletingLastPathComponent
            return SpotlightFolder(path: item.path, project: (project as NSString).lastPathComponent, kind: kind,
                                   sizeBytes: item.sizeBytes,
                                   state: current(item.path) ?? (item.status == .fenced ? .fenced : .notFenced),
                                   title: folder.isEmpty ? kind.title : "\(folder) · \(kind.title)")
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        let indexing = run.indexingLine?.lowercased().contains("disabled") == true ? "Indexing is off." : "Indexing is on."
        let sentence: String
        switch run.verdict {
        case .progressing: sentence = "Spotlight is busy indexing right now."
        case .idleOrComplete: sentence = "Spotlight is idle: indexing is finished or waiting."
        case .notRunning: sentence = "Spotlight isn't indexing at the moment."
        case .unknown: sentence = "The audit couldn't tell whether indexing is stuck."
        }
        var details: [String] = []
        if let mds = run.mdsLine { details.append("Spotlight's helper processes: \(mds).") }
        if let update = run.recentUpdateLine {
            // "macOS 27.0.1     27.0.1     10/15/2026, 15:08:25": the name and version, and when
            let parts = update.components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let what = parts.count >= 2 ? "\(parts[0]), \(parts[parts.count - 1])" : update
            details.append("A recent macOS update (\(what)) makes a full reindex expected; it can take hours.")
        }
        return SpotlightReview(status: indexing, verdict: run.verdict, verdictSentence: sentence, folders: folders,
                               unfencedBulkBytes: run.unfencedBulkBytes, deepCheckCommand: run.deepCheckCommand,
                               rebuildCommand: run.rebuildCommand, statusDetails: details)
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
