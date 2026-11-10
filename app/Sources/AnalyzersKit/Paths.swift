import Foundation

/// Canonical file locations shared by every module. Mirrors the bash suite's
/// layout (~/mac-analyzers/reports/{memory,storage}, ~/scripts/config.local.sh).
///
/// This file is the paths only. Next to it:
///   Navigation/NotifyChannel.swift   the notification names the app and CLI share
///   Navigation/SettingsOpener.swift  opening the Settings window from anywhere
public enum AnalyzersPaths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let memoryReports = home.appending(path: "mac-analyzers/reports/memory")
    public static let storageReports = home.appending(path: "mac-analyzers/reports/storage")

    public static let guardLog = memoryReports.appending(path: "guard.log")
    public static let memoryAutoCleanLog = memoryReports.appending(path: "auto-clean.log")
    public static let reclaimLog = memoryReports.appending(path: "reclaim.log")
    public static let storageAutoCleanLog = storageReports.appending(path: "auto-clean.log")
    public static let loginItemsAuditLog = storageReports.appending(path: "login-items-audit.log")
    public static let spotlightAuditLog = storageReports.appending(path: "spotlight-audit.log")
    public static let tempCleanLog = storageReports.appending(path: "temp-clean.log")

    public static let guardPauseFlag = memoryReports.appending(path: ".guard-paused")

    /// Where the engine scripts actually live. The app bundles its own copy,
    /// so a downloaded app works with nothing else installed; a source clone
    /// still wins when present, because that is the copy the developer edits.
    public static let suiteRoot: URL = {
        let clone = home.appending(path: "mac-analyzers")
        if FileManager.default.isExecutableFile(
            atPath: clone.appending(path: "memory-analyzer/memory-guard.sh").path) {
            return clone
        }
        if let bundled = Bundle.main.resourceURL?.appending(path: "engine"),
           FileManager.default.isExecutableFile(
            atPath: bundled.appending(path: "memory-analyzer/memory-guard.sh").path) {
            return bundled
        }
        return clone
    }()

    /// True when the engine we found is the one inside the app bundle — the
    /// Setup checklist says so rather than implying a clone exists.
    public static var usingBundledEngine: Bool {
        suiteRoot.path.contains(".app/Contents/Resources/engine")
    }

    /// Settings always live in the user's own folder, never inside the app
    /// bundle (which is replaced wholesale on every update).
    public static let configLocal = home
        .appending(path: "mac-analyzers/config.local.sh")

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

    /// Every forensics dump, newest first (dated subdirs, guard-critical-*).
    public static func allForensics() -> [URL] {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(
            at: memoryReports, includingPropertiesForKeys: nil
        ) else { return [] }
        var found: [(URL, Date)] = []
        for day in days where day.hasDirectoryPath {
            guard let files = try? fm.contentsOfDirectory(
                at: day, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for f in files where f.lastPathComponent.hasPrefix("guard-critical-") {
                let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                found.append((f, mtime))
            }
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
