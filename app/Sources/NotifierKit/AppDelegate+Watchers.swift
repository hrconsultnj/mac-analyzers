import AppKit
import AnalyzersKit

/// The background watchers: new login items, and new releases.
extension AppDelegate {

    /// Launch + 6-hourly: alert when something NEW installs itself to run at
    /// login/boot. First run seeds the baseline silently.
    func startPersistenceWatcher() {
        Task { @MainActor in
            while true {
                let additions = await Task.detached(priority: .utility) {
                    PersistenceWatcher.checkForAdditions()
                }.value
                if !additions.isEmpty {
                    let names = additions
                        .map { ($0 as NSString).lastPathComponent }
                        .joined(separator: ", ")
                    NotificationPoster.shared.post(
                        title: additions.count == 1
                            ? "New Login Item Installed"
                            : "\(additions.count) New Login Items Installed",
                        subtitle: Names.startupChanges,
                        message: "\(names). Click to review — nothing was blocked.",
                        sound: nil, logPath: nil, paneTarget: "log:persistence")
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    /// Checks for a newer release at launch and every 6 hours; notifies ONCE
    /// per version — clicking the notification opens the Update pane.
    func startUpdateWatcher() {
        Task { @MainActor in
            while true {
                if let latest = await UpdateChecker.latestVersion(),
                   UpdateChecker.isNewer(latest, than: BuildInfo.current.version),
                   UserDefaults.standard.string(forKey: "updateNotifiedFor") != latest {
                    NotificationPoster.shared.post(
                        title: "\(Names.app) \(Names.State.updateAvailable)",
                        subtitle: "v\(latest)",
                        message: "You're on v\(BuildInfo.current.shortVersion). Click to open \(Names.Screen.updates) and install with one click.",
                        sound: nil, logPath: nil, paneTarget: "update")
                    UserDefaults.standard.set(latest, forKey: "updateNotifiedFor")
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }
}
