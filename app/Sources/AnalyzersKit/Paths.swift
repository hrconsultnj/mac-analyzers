import Foundation
import Synchronization

/// Canonical file locations shared by every module. The same chain as
/// `lib/paths.sh`: an explicit data directory, then `~/sparehold` when it
/// already holds data, then an existing `~/mac-analyzers`, then Application
/// Support. Nothing here moves or deletes `~/mac-analyzers`.
///
/// This file is the paths only. Next to it:
///   Navigation/NotifyChannel.swift   the notification names the app and CLI share
///   Navigation/SettingsOpener.swift  opening the Settings window from anywhere
public enum AnalyzersPaths {
    /// The folder a probe that judges itself runs in instead of the person's home (`useHome`); read once, when `home` is
    /// first used, so it must be set before anything else resolves a path.
    private static let homeChoice = Mutex<URL?>(nil)

    /// Test support: every path below resolves under `url` instead of the account's home folder. Only the probes that
    /// judge themselves call it (the interface is `@_spi(TestSupport)`, which the app people install cannot import),
    /// before anything else asks for a path; they check afterwards that nothing resolved into the real home.
    @_spi(TestSupport) public static func useHome(_ url: URL) {
        homeChoice.withLock { $0 = url }
    }

    public static let home: URL = homeChoice.withLock { $0 } ?? FileManager.default.homeDirectoryForCurrentUser

    public static let memoryReports = userRoot.appending(path: "reports/memory")
    public static let storageReports = userRoot.appending(path: "reports/storage")

    /// Where the APP WRITES its own records — never the bundle. Whichever copy
    /// of the engine is being read from, records stay in this folder.
    public static let userRoot: URL = resolveUserRoot()
    public static let userReports = userRoot.appending(path: "reports")

    /// A path under the home folder, shown with a leading `~`.
    public static func displayPath(_ url: URL) -> String {
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }

    /// Where the engine scripts are read from (the clone, or the bundle).
    /// Earlier builds wrote some records under here.
    static var legacyReports: URL { suiteRoot.appending(path: "reports") }

    /// The app-written record `name` under `userReports`, created on demand.
    /// First use carries an older copy across from the engine's own `reports`
    /// folder (see `carryOver`).
    static func userRecord(_ name: String) -> URL {
        let new = userReports.appending(path: name)
        carryOver(from: legacyReports.appending(path: name), to: new)
        return new
    }

    /// Copies `old` to `new` when they are different files, `old` exists and
    /// `new` does not. Never deletes `old` (it may sit in a signed bundle) and
    /// never overwrites `new`. Does nothing when both resolve to one path.
    @discardableResult
    static func carryOver(from old: URL, to new: URL) -> Bool {
        let fm = FileManager.default
        let oldPath = old.standardizedFileURL.resolvingSymlinksInPath().path
        let newPath = new.standardizedFileURL.resolvingSymlinksInPath().path
        guard oldPath != newPath,
              fm.fileExists(atPath: old.path),
              !fm.fileExists(atPath: new.path)
        else { return false }
        try? fm.createDirectory(at: new.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        return (try? fm.copyItem(at: old, to: new)) != nil
    }

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
    /// An existing `~/mac-analyzers` checkout wins over the bundle until the
    /// person moves the engine.
    public static let suiteRoot: URL = resolveSuiteRoot()

    /// True when the engine we found is the one inside the app bundle — the
    /// Setup checklist says so rather than implying a clone exists.
    public static var usingBundledEngine: Bool {
        suiteRoot.path.contains(".app/Contents/Resources/engine")
    }

    /// Settings always live in the user's own folder, never inside the app
    /// bundle (which is replaced wholesale on every update).
    public static let configLocal = userRoot.appending(path: "config.local.sh")

    /// A probe home (`useHome`) stands in for the account, so the data-root
    /// environment variables are not read then: a probe must not follow them
    /// out of its sandbox into the person's files.
    private static func resolveUserRoot() -> URL {
        let probing = homeChoice.withLock { $0 != nil }
        if !probing {
            let env = ProcessInfo.processInfo.environment
            for key in ["SPAREHOLD_DATA_DIR", "SPAREHOLD_DIR", "MAC_ANALYZERS_DIR"] {
                if let value = env[key], !value.isEmpty {
                    return URL(fileURLWithPath: value, isDirectory: true)
                }
            }
        }
        let sparehold = home.appending(path: "sparehold")
        if containsData(sparehold) { return sparehold }
        let legacy = home.appending(path: "mac-analyzers")
        if containsData(legacy) { return legacy }
        return home.appending(path: "Library/Application Support/Sparehold")
    }

    private static func resolveSuiteRoot() -> URL {
        let probing = homeChoice.withLock { $0 != nil }
        if !probing, let value = ProcessInfo.processInfo.environment["SPAREHOLD_SUITE_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        let sparehold = home.appending(path: "sparehold")
        if hasEngine(sparehold) { return sparehold }
        let legacy = home.appending(path: "mac-analyzers")
        if hasEngine(legacy) { return legacy }
        if let bundled = Bundle.main.resourceURL?.appending(path: "engine"), hasEngine(bundled) {
            return bundled
        }
        return legacy
    }

    private static func containsData(_ directory: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.appending(path: "config.local.sh").path) { return true }
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: directory.appending(path: "reports").path, isDirectory: &isDirectory),
           isDirectory.boolValue { return true }
        return fm.fileExists(atPath: directory.appending(path: ".git").path)
    }

    private static func hasEngine(_ directory: URL) -> Bool {
        FileManager.default.isExecutableFile(
            atPath: directory.appending(path: "memory/memory-guard.sh").path)
    }

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
