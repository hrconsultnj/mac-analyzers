import Foundation

/// Copies `com.mac-analyzers.app` preferences into this process's domain once.
/// A key that already has a value is left alone. Call it before any preference read.
public enum DefaultsMigrator {
    public static let sentinel = "sparehold.migratedFromMacAnalyzers.v1"
    public static let wasMigratedKey = "sparehold.wasMigratedFromLegacyBundle"

    /// True after a launch that copied at least one legacy preference.
    public static var wasMigratedFromLegacyBundle: Bool {
        UserDefaults.standard.bool(forKey: wasMigratedKey)
    }

    public static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: sentinel) == nil else { return }
        let legacy = defaults.persistentDomain(forName: AppIdentity.legacyBundleID) ?? [:]
        var copied = false
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied = true
        }
        if copied {
            defaults.set(true, forKey: wasMigratedKey)
        }
        defaults.set(true, forKey: sentinel)
    }
}
