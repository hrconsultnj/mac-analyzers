import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import AnalyzersKit
import NotifierKit
import UIComponents

/// The Setup checklist — the screen that answers "does this actually work on
/// my Mac?" with evidence rather than reassurance. Every row was detected,
/// and every row that is not green carries the button that fixes it.
struct SetupSettingsView: View {

    @Environment(GuardLogStore.self) private var store
    @State private var report: SetupReport?
    @State private var working: String?
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        PaneScaffold(symbol: "checklist.checked", color: .green, title: "Setup",
                     caption: "What this Mac can actually do right now. Every line was checked, not assumed.") {
            if let report {
                progress(report)
                if let message {
                    Section {
                        Label(message, systemImage: messageIsError
                              ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(messageIsError ? Tokens.Status.destructive.tint
                                                            : Tokens.Status.safe.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // blocking first — a checklist that buries the thing stopping
                // the product behind six green ticks has failed at its job
                group("NEEDS ATTENTION", report.checks.filter { $0.verdict == .blocking })
                group("WORTH DOING", report.checks.filter { $0.verdict == .degraded })
                group("YOUR CHOICE", report.checks.filter { $0.verdict == .unset })
                group("WORKING", report.checks.filter { $0.verdict == .ready })
                Section {
                    Text("This screen stays in the sidebar after everything is green. Permissions can be withdrawn and background jobs can be unloaded by macOS, so it is worth a look if something stops behaving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section { Text("Checking this Mac…").foregroundStyle(.secondary) }
            }
        }
        .task { await load() }
    }

    // MARK: - pieces

    @ViewBuilder private func progress(_ report: SetupReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HStack {
                    Text(headline(report))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(report.ready) of \(report.total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(report.ready), total: Double(report.total))
                    .tint(report.isUsable ? Tokens.Status.safe.tint : Tokens.Status.destructive.tint)
                Text(subhead(report))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headline(_ report: SetupReport) -> String {
        if !report.isUsable { return "Not protected yet" }
        if report.isComplete { return "Everything is set up" }
        return "Protected"
    }

    private func subhead(_ report: SetupReport) -> String {
        if !report.isUsable {
            return "Something below stops Mac Analyzers doing its job. Each one has a button that fixes it."
        }
        if report.isComplete {
            return "Your Mac is watched, tidied on a schedule, and everything it needs has been granted."
        }
        return "The essentials are working. The rest are improvements you can make whenever you like."
    }

    @ViewBuilder private func group(_ title: String, _ checks: [SetupCheck]) -> some View {
        if !checks.isEmpty {
            Section(title) {
                ForEach(checks) { check in
                    row(check)
                }
            }
        }
    }

    @ViewBuilder private func row(_ check: SetupCheck) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: symbol(check.verdict))
                .foregroundStyle(tone(check.verdict).tint)
                .font(.system(size: Tokens.Icon.row))
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(check.title).font(.callout.weight(.medium))
                Text(check.why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // the evidence, visually separated from the sales pitch
                Text(check.detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(check.verdict == .ready ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: Tokens.Space.m)
            if let title = check.repairTitle, check.repair != .none {
                Button(working == check.id ? "Working…" : title) {
                    Task { await repair(check) }
                }
                .disabled(working != nil)
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 2)
    }

    private func symbol(_ verdict: SetupCheck.Verdict) -> String {
        switch verdict {
        case .ready: "checkmark.circle.fill"
        case .blocking: "exclamationmark.octagon.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unset: "circle.dashed"
        }
    }

    private func tone(_ verdict: SetupCheck.Verdict) -> Tokens.Tone {
        switch verdict {
        case .ready: Tokens.Status.safe
        case .blocking: Tokens.Status.destructive
        case .degraded: Tokens.Status.caution
        case .unset: Tokens.Status.inert
        }
    }

    // MARK: - probing

    private func load() async {
        // the two system permissions answer asynchronously; everything else
        // is a file/launchctl read that belongs off the main actor
        let notifications = await notificationCheck()
        let login = loginItemCheck()
        await awaitLoad({ SetupAudit.probe(notifications: notifications, loginItem: login) },
                        ttl: 1) { report = $0 }
    }

    private func notificationCheck() async -> SetupCheck {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            let alerts = settings.alertSetting == .enabled
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: alerts ? .ready : .degraded,
                detail: alerts
                    ? "Allowed, and alerts are visible."
                    : "Allowed, but alerts are switched off in System Settings, so you will only see them in Notification Centre.",
                repair: alerts ? .sendTestNotification : .openNotificationSettings,
                repairTitle: alerts ? "Send a test" : "Open the setting")
        case .denied:
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: .degraded,
                detail: "Turned off. Mac Analyzers still works, but it will act silently.",
                repair: .openNotificationSettings, repairTitle: "Open the setting")
        default:
            return SetupCheck(
                id: "notifications", title: "Alerts when something happens",
                why: "Tells you when an app was stopped or space was reclaimed, so nothing happens behind your back.",
                verdict: .unset,
                detail: "Not asked yet.",
                repair: .requestNotifications, repairTitle: "Allow alerts")
        }
    }

    /// Read live every time. A cached login-item status is how an app ends up
    /// claiming it starts at login when the user removed it last week.
    private func loginItemCheck() -> SetupCheck {
        let why = "Puts the menu-bar icon back after a restart. The background protection runs either way."
        switch SMAppService.mainApp.status {
        case .enabled:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .ready, detail: "Enabled.")
        case .requiresApproval:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .degraded,
                              detail: "Waiting for your approval in System Settings › General › Login Items.",
                              repair: .openLoginItemSettings, repairTitle: "Open the setting")
        case .notFound:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .degraded,
                              detail: "macOS does not recognise this copy of the app. Move it to your Applications folder and try again.",
                              repair: .enableLoginItem, repairTitle: "Try again")
        default:
            return SetupCheck(id: "login", title: "Opens when you log in", why: why,
                              verdict: .unset, detail: "Not enabled.",
                              repair: .enableLoginItem, repairTitle: "Turn it on")
        }
    }

    // MARK: - repairs

    private func repair(_ check: SetupCheck) async {
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
            NotificationCenter.default.post(name: NotifyChannel.openPaneInternal,
                                            object: nil, userInfo: ["target": target])

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

