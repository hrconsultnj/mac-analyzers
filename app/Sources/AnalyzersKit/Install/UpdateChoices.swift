import Foundation

/// What a person has chosen about update notices, kept in the defaults: whether the app checks by itself, and the version
/// they asked not to hear about again. One place, read by the update state, the 6-hourly watcher and the Updates screen.
///
/// Nothing here installs anything: installing always asks (the Install button, or `upgrade.command` in Terminal).
public enum UpdateChoices {
    public static let automaticKey = "updateCheckAutomatically"
    public static let skippedKey = "updateSkippedVersion"
    /// The version the last notice announced: the watcher says each version once.
    public static let notifiedKey = "updateNotifiedFor"

    /// Whether the app checks by itself (at launch and every 6 hours) and says so once per version. On unless switched off.
    public static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: automaticKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }

    /// The version "Skip This Version" was pressed for ("2.73.1", "2.73.1-beta.2"); nil when none.
    public static var skippedVersion: String? {
        UserDefaults.standard.string(forKey: skippedKey)
    }

    public static func skip(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedKey)
    }

    /// Skipping is for that version alone: a newer one is announced again.
    public static func isSkipped(_ version: String) -> Bool { skippedVersion == version }

    /// "Remind Me Later": the version is announced again at the next automatic check, as if it had not been said.
    public static func remindLater() {
        UserDefaults.standard.removeObject(forKey: notifiedKey)
    }

    /// Whether the 6-hourly watcher should post a notice for `latest` now: it checks by itself, the version was not skipped
    /// and has not been announced.
    public static func shouldNotify(of latest: String) -> Bool {
        automatic && !isSkipped(latest) && UserDefaults.standard.string(forKey: notifiedKey) != latest
    }

    public static func didNotify(of latest: String) {
        UserDefaults.standard.set(latest, forKey: notifiedKey)
    }
}
