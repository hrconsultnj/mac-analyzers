import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import AnalyzersKit
import NotifierKit

/// The action behind each row's button: what it does, and the sentence that says what came of it.
extension SetupView {

    func perform(_ item: SetupItem) async {
        guard let action = item.action else { return }
        // an example state is only looked at: nothing is changed on this Mac from it
        if fixture != nil, !isNavigation(action) { return }
        working = item.id
        message = nil
        defer { working = nil }

        switch action {
        case .installAgents:
            let installed = await installAgents()
            messageIsError = !installed.ok
            message = installed.text

        case .allowNotifications:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            messageIsError = !granted
            message = granted ? "Notifications allowed. Send a test to see one."
                              : "Notifications weren't allowed. You can change your mind in System Settings › Notifications."

        case .sendTest:
            NotificationPoster.shared.post(
                title: "Mac Analyzers", subtitle: "Test",
                message: "Notifications are working. This is what you will see when something happens.",
                sound: nil, logPath: nil, pid: nil)
            messageIsError = false
            message = "Test sent. If nothing appeared, check Notification Center."

        case .enableLogin:
            do {
                try SMAppService.mainApp.register()
                messageIsError = false
                message = "Turned on. Mac Analyzers will open when you log in."
            } catch {
                messageIsError = true
                message = "Couldn't turn it on: \(error.localizedDescription)"
            }

        case .timeMachineAllow:
            let outcome = await TimeMachinePermission.allow()
            apply(outcome, done: "Allowed. Mac Analyzers can now delete Time Machine's local snapshots without asking each time.")

        case .timeMachineRemove:
            let outcome = await TimeMachinePermission.revoke()
            apply(outcome, done: "Permission removed. Thinning snapshots will ask for your password again.")

        case .writeConfig:
            do {
                try ConfigStore().save()
                messageIsError = false
                message = "Settings file created with the defaults."
            } catch {
                messageIsError = true
                message = "Couldn't write the settings file: \(error.localizedDescription)"
            }

        case .setMemoryCap(let mb):
            let config = ConfigStore()
            config.memory.hardCapMB = mb
            do {
                try config.save()
                messageIsError = false
                message = "Memory limit set to \(ByteSize.text(Int64(mb) * 1_048_576, .headline))."
            } catch {
                messageIsError = true
                message = "Couldn't save the new limit: \(error.localizedDescription)"
            }

        case .change(let target), .showInActivity(let target):
            navigator.open(target: target)

        case .openSettings(let pane):
            // the row turns into the guidance, and watches for the change
            handoff.begin(item.id, pane: pane)
        }

        await load()
        store.reload()
    }

    private func isNavigation(_ action: SetupAction) -> Bool {
        switch action {
        case .change, .showInActivity, .openSettings: true
        default: false
        }
    }

    private func apply(_ outcome: TimeMachinePermission.Outcome, done: String) {
        switch outcome {
        case .done: messageIsError = false; message = done
        case .cancelled: messageIsError = false; message = "Nothing was changed."
        case .failed(let text): messageIsError = true; message = TimeMachinePermission.installFailureText(text)
        }
    }

    /// Runs both installers as one tracked job, so it shows in the toolbar and Activity, can be stopped here or there, and
    /// finishes even if this window closes. They are sudo-free by design: everything they touch is in the person's own
    /// launchd domain.
    private func installAgents() async -> (ok: Bool, text: String) {
        let job = jobs.enqueue(JobRequest(kind: .installAgents, intent: .run), trigger: .user)
        installJob = job
        return await finishInstall(job)
    }

    /// The window was closed while the agents were being installed: show the install still working, then say what is true
    /// once it ends.
    func adoptRunningInstall() async {
        guard let running = jobs.latest(.installAgents, intents: [.run]), running.isActive else { return }
        installJob = running
        working = "adopted"
        defer { working = nil }
        let outcome = await finishInstall(running)
        messageIsError = !outcome.ok
        message = outcome.text
        await load()
    }

    private func finishInstall(_ job: Job) async -> (ok: Bool, text: String) {
        await job.waitUntilFinished()
        if case .cancelled = job.state {
            return (false, "Stopped. Some background jobs may already be installed: the Background tab shows which.")
        }
        if let message = job.failureMessage, job.exitCode == 127 {
            return (false, message)      // the engine scripts are missing; nothing else to prove
        }
        // prove it rather than announce it
        let status = await Task.detached(priority: .userInitiated) { EngineStatus.probe() }.value
        let loaded = (status.guardAgent == .loaded ? 1 : 0) + status.cleanerAgents.values.filter { $0 == .loaded }.count
        let total = EngineStatus.cleanerLabels.count + 1
        return loaded == total
            ? (true, "Background protection is on: all \(total) background jobs are loaded.")
            : (false, "\(loaded) of \(total) background jobs loaded. Open the Schedule screen to see which are missing.")
    }
}
