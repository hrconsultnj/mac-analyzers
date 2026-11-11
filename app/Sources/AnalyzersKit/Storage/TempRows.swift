import Foundation

/// The verdict on one item found in temp and agent folders. The engine's
/// tokens (`DRY`, `IN USE`, `KEPT`, `MANAGED`) are mapped to words here and
/// nowhere else.
public enum TempState: String, CaseIterable, Identifiable, Sendable {
    case ready, tooRecent, inUse, protected, notYours, leftAlone, sizedOnly, cleared, failed
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ready: Names.Temp.ready
        case .tooRecent: Names.Temp.tooRecent
        case .inUse: Names.Temp.inUse
        case .protected: Names.Temp.protected
        case .notYours: Names.Temp.notYours
        case .leftAlone: Names.Temp.leftAlone
        case .sizedOnly: Names.Temp.sizedOnly
        case .cleared: Names.Temp.cleared
        case .failed: Names.Temp.failed
        }
    }

    init(_ status: TempItem.Status) {
        switch status {
        case .dry: self = .ready
        case .recent: self = .tooRecent
        case .inUse: self = .inUse
        case .protected: self = .protected
        case .notYours: self = .notYours
        case .trashed, .deleted: self = .cleared
        case .failed: self = .failed
        case .skip, .keep, .system: self = .leftAlone
        case .history, .kept, .managed: self = .sizedOnly
        }
    }
}

/// One thing in a temp or agent folder: named, sized, and judged.
public struct TempRow: Identifiable, Hashable, Sendable {
    public let path: String
    public let title: String
    public let group: String
    public let state: TempState
    public let sizeBytes: Int64
    /// The verdict in a sentence ("Changed in the last 24 hours.").
    public let outcome: String
    /// How many items a family row stands for; 1 for a single item.
    public let count: Int
    /// Disk images mounted from inside it, which an apply ejects first.
    public let ejects: [String]

    /// The engine's key — what `--only-paths` is given. A family row's key is
    /// its `…*` token, which stands for exactly the siblings the engine finds.
    public var id: String { path }
    public var isReady: Bool { state == .ready }
    public var shortPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

/// A disk image mounted inside a temp folder.
public struct TempDiskImage: Identifiable, Hashable, Sendable {
    public let mountPoint: String
    public let imagePath: String
    public let sizeBytes: Int64
    /// Other images mounted from files inside this one; they go when it does.
    public let alsoEjects: [String]
    public var id: String { mountPoint }
    public var name: String { (mountPoint as NSString).lastPathComponent }
}

/// What an audit of temp and agent folders found, ready for the table.
public struct TempReview: Sendable {
    public let rows: [TempRow]
    public let diskImages: [TempDiskImage]
    /// The numbers at the top: free space, temp on disk, agent folders.
    public let freeSpace: String?
    public let tempOnDisk: String?
    public let agentFolders: String?

    public var ready: [TempRow] { rows.filter(\.isReady) }
    public var readyBytes: Int64 { ready.reduce(0) { $0 + $1.sizeBytes } }
    public var leftAloneCount: Int { rows.filter { $0.state != .ready && $0.state != .sizedOnly && $0.state != .cleared }.count }

    public static func build(from run: TempCleanRun) -> TempReview {
        let rows = run.items.map { item -> TempRow in
            let reason = item.reason
            let name = TempNaming.name(path: item.path, section: item.section, reason: reason,
                                       isGroup: item.isGroup, count: item.count,
                                       isCurrent: reason == "current version")
            return TempRow(path: item.path, title: name.title, group: name.group,
                           state: TempState(item.status), sizeBytes: item.sizeBytes,
                           outcome: sentence(item, reason: reason), count: item.count, ejects: item.ejects)
        }
        let images = run.mountedNow.map {
            TempDiskImage(mountPoint: $0.mountPoint, imagePath: $0.imagePath, sizeBytes: $0.sizeBytes,
                          alsoEjects: $0.alsoEjects)
        }
        return TempReview(rows: rows, diskImages: images, freeSpace: run.freeSpace,
                          tempOnDisk: run.tempOnDisk, agentFolders: run.agentFolders)
    }

    /// One sentence for the row: the engine's reason, spelled out.
    static func sentence(_ item: TempItem, reason: String?) -> String {
        guard let reason else {
            switch TempState(item.status) {
            case .ready: return "Idle long enough to clear."
            case .cleared: return "Cleared."
            default: return ""
            }
        }
        // npx rows end with the package name after " · "; the name is the title,
        // and a ready one carries nothing else
        if item.path.contains("/.npm/_npx/") {
            let parts = reason.components(separatedBy: " · ")
            if parts.count == 1, TempNaming.looksLikePackage(reason) { return "Not used in the last 14 days." }
        }
        var text = reason.components(separatedBy: " · ").first ?? reason
        text = text.replacingOccurrences(of: "24h", with: "24 hours")
        text = text.replacingOccurrences(of: "Claude Code deletes", with: "Claude Code removes")
        if text.hasPrefix("changed in the last") { text = "Changed in the last" + text.dropFirst("changed in the last".count) }
        text = text.replacingOccurrences(of: " (cleanupPeriodDays)", with: "")
        let first = text.prefix(1).uppercased() + text.dropFirst()
        let sentence = first.hasSuffix(".") ? first : first + "."
        return item.isGroup ? "\(item.count) items. \(sentence)" : sentence
    }
}
