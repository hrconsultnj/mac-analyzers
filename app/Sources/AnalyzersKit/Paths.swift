import Foundation

/// Canonical file locations shared by every module. Mirrors the bash suite's
/// layout (~/mac-analyzers/reports/{memory,storage}, ~/scripts/config.local.sh).
public enum AnalyzersPaths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let memoryReports = home.appending(path: "mac-analyzers/reports/memory")
    public static let storageReports = home.appending(path: "mac-analyzers/reports/storage")

    public static let guardLog = memoryReports.appending(path: "guard.log")
    public static let memoryAutoCleanLog = memoryReports.appending(path: "auto-clean.log")
    public static let reclaimLog = memoryReports.appending(path: "reclaim.log")
    public static let storageAutoCleanLog = storageReports.appending(path: "auto-clean.log")
    public static let loginItemsAuditLog = storageReports.appending(path: "login-items-audit.log")

    public static let guardPauseFlag = memoryReports.appending(path: ".guard-paused")

    public static let suiteRoot = home.appending(path: "mac-analyzers")
    public static let configLocal = suiteRoot.appending(path: "config.local.sh")

    /// Newest guard-critical forensics dump, if any (they live in dated subdirs).
    public static func latestForensics() -> URL? {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(
            at: memoryReports, includingPropertiesForKeys: nil
        ) else { return nil }
        var newest: (URL, Date)?
        for day in days where day.hasDirectoryPath {
            guard let files = try? fm.contentsOfDirectory(
                at: day, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for f in files where f.lastPathComponent.hasPrefix("guard-critical-") {
                let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                if newest == nil || mtime > newest!.1 { newest = (f, mtime) }
            }
        }
        return newest?.0
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

/// Name of the distributed notification the CLI shim posts and the app observes.
public enum NotifyChannel {
    public static let name = "com.mac-analyzers.notify"
    public static let appBundleID = "com.mac-analyzers.app"
    /// In-process signal: "open the Settings window" (Dock click, notification
    /// default action). Posted by AppKit code, observed by the SwiftUI anchor
    /// window, which holds the openSettings environment action.
    public static let openSettingsInternal = Notification.Name("com.mac-analyzers.open-settings")
}
