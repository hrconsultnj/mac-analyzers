import Foundation

/// What a Storage item is called, and what it belongs to, in one place: the words the Storage screens use for a
/// cleaned path, for any screen that has to name one without a review in hand (Undo's items, Trends' "Removed by
/// Project"). A path under a project is "<kind> in <project>" with the project as its group; an app's cache is the
/// app's name under "App Caches"; a tool's cache the tool's name under "Tool Caches"; a temp or agent folder the
/// name Temp & Agents gives it; anything else the file's own name under its folder's kind (Downloads, Screenshots).
public struct StorageItemName: Sendable, Equatable {
    /// The project, app, agent or kind it belongs to: what a table groups under.
    public let group: String
    /// What it is called inside that group.
    public let title: String
}

public enum StorageNaming {

    /// `roots` are the folders the cleanup sweeps for projects (`CacheReview.roots(in:)` from a run), when known.
    public static func name(forPath path: String, roots: [String] = []) -> StorageItemName {
        let home = NSHomeDirectory()
        let lower = path.lowercased()
        // temp and agent folders
        let tempish = lower.hasPrefix("/tmp") || lower.hasPrefix("/private/tmp") || lower.hasPrefix("/private/var/folders")
            || lower.hasPrefix("/var/folders") || lower.contains("/.claude/") || lower.contains("/.codex/") || lower.contains("/.npm/_npx")
        if tempish {
            let name = TempNaming.name(path: path, section: "", reason: nil, isGroup: false, count: 1, isCurrent: false)
            return StorageItemName(group: name.group, title: name.title)
        }
        // downloads and screenshots: the file's own name
        if path.hasPrefix(home + "/Downloads/") { return StorageItemName(group: Names.Screen.downloads, title: (path as NSString).lastPathComponent) }
        if lower.contains("/screenshots/") { return StorageItemName(group: Names.Download.screenshots, title: (path as NSString).lastPathComponent) }
        // caches and builds: the same words the Caches & Builds review uses
        let section = lower.contains("/library/caches/") && !lower.contains("/library/caches/pip") ? "app caches"
            : (lower.contains("/library/") || lower.contains("/.cache/") || lower.contains("/.cargo/") || lower.contains("/.gradle/") || lower.contains("/.bun/")) ? "tool caches" : "build caches"
        let row = CacheReview.pathRow(path: path, bytes: 0, status: .dry, section: section, roots: roots, lastUsed: nil)
        return StorageItemName(group: row.group ?? Names.StorageTab.appCaches, title: row.title)
    }
}
