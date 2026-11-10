import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import AnalyzersKit
import NotifierKit
import UIComponents

/// The fix behind each red row: repairs, agent install and opening System Settings.
extension SetupSettingsView {

    // MARK: - repairs

    func repair(_ check: SetupCheck) async {
        working = check.id
        message = nil
        defer { working = nil }

        switch check.repair {
        case .installAgents:
            let installed = await installAgents()
            messageIsError = !installed.ok
            message = installed.text

        case .requestNotifications:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            messageIsError = !granted
            message = granted
                ? "Alerts allowed. Send a test to see one."
                : "Alerts were not allowed. You can change your mind in System Settings › Notifications."

        case .sendTestNotification:
            NotificationPoster.shared.post(
                title: "Mac Analyzers", subtitle: "Test",
                message: "Alerts are working. This is what you will see when something happens.",
                sound: nil, logPath: nil, pid: nil)
            messageIsError = false
            message = "Test sent. If nothing appeared, check Notification Centre."

        case .openNotificationSettings:
            open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")

        case .enableLoginItem:
            do {
                try SMAppService.mainApp.register()
                messageIsError = false
                message = "Enabled. Mac Analyzers will open when you log in."
            } catch {
                messageIsError = true
                message = "Could not enable it: \(error.localizedDescription)"
            }

        case .openLoginItemSettings:
            SMAppService.openSystemSettingsLoginItems()

        case .writeConfig:
            do {
                try ConfigStore().save()
                messageIsError = false
                message = "Settings file created with the defaults."
            } catch {
                messageIsError = true
                message = "Could not write the settings file: \(error.localizedDescription)"
            }

        case .setMemoryCap(let mb):
            let config = ConfigStore()
            config.memory.hardCapMB = mb
            do {
                try config.save()
                messageIsError = false
                message = "Memory limit set to \(mb) MB."
            } catch {
                messageIsError = true
                message = "Could not save the new limit: \(error.localizedDescription)"
            }

        case .openPane(let target):
            navigator.open(target: target)

        case .openFullDiskAccess:
            open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")

        case .openAutomationSettings:
            open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation")

        case .none:
            break
        }

        await load()
        store.reload()
    }

    /// Runs both installers. They are sudo-free by design — everything they
    /// touch is in the user's own launchd domain.
    private func installAgents() async -> (ok: Bool, text: String) {
        for script in ["memory-analyzer/memory-manage-agents.sh",
                       "storage-analyzer/storage-manage-agents.sh"] {
            let url = AnalyzersPaths.suiteRoot.appending(path: script)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                return (false, "Could not find \(script) — the app's copy of the analyzer scripts is incomplete.")
            }
            _ = await ActionRunner.run(script: url, args: ["install"])
        }
        // prove it rather than announce it
        let status = await Task.detached(priority: .userInitiated) { EngineStatus.probe() }.value
        let loaded = (status.guardAgent == .loaded ? 1 : 0)
            + status.cleanerAgents.values.filter { $0 == .loaded }.count
        let total = EngineStatus.cleanerLabels.count + 1
        return loaded == total
            ? (true, "Automatic protection is on — all \(total) background jobs are loaded.")
            : (false, "\(loaded) of \(total) background jobs loaded. Open the Schedule screen to see which are missing.")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
