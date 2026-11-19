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

    /// The rules engine, in Watching only: a look a minute, a would-have row for what a rule would do. It stops, quits and
    /// signals nothing; the guard script does what it always did.
    func startRulesWatcher() {
        Task {
            await RulesEngine.shared.startWatching { await MainActor.run { RulesEngine.frontAppNames() } }
        }
    }

    /// Checks for a newer release at launch and every 6 hours; notifies ONCE
    /// per version — clicking the notification opens the Update pane.
    func startUpdateWatcher() {
        Task { @MainActor in
            while true {
                // switched off: no checking and no notices (the Updates screen and "Check for Updates…" still look when asked)
                if UpdateChoices.automatic,
                   let latest = await UpdateChecker.latestVersion(),
                   UpdateChecker.isNewer(latest, than: BuildInfo.current.version),
                   UpdateChoices.shouldNotify(of: latest) {
                    NotificationPoster.shared.post(
                        title: "\(Names.app) \(Names.State.updateAvailable)",
                        subtitle: "v\(latest)",
                        message: "You're on \(BuildInfo.current.versionText). Click to open \(Names.Screen.updates) and install with one click.",
                        sound: nil, logPath: nil, paneTarget: "update")
                    UpdateChoices.didNotify(of: latest)
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }
}
