import AppKit
import AnalyzersKit
import UserNotifications

/// Posts suite notifications and handles their clicks. Because the menu-bar
/// app is persistent, the delegate is always alive — clicks are handled by a
/// live delegate, never the cold-relaunch path the standalone notifier needed.
///
/// Click contract (user feedback: "showing me the log doesn't do anything —
/// give us options"): the notification BODY click opens the app (Settings →
/// where the actionable buttons live). Buttons: "Open Log" for the receipt,
/// and — when the sender attached a live pid — "Stop Process" right from the
/// notification.
@MainActor
public final class NotificationPoster: NSObject {

    public static let shared = NotificationPoster()

    private let center = UNUserNotificationCenter.current()
    private static let eventCategory = "MA_EVENT"
    private static let actionableCategory = "MA_ACTIONABLE"
    private static let openAppAction = "OPEN_APP"
    private static let openLogAction = "OPEN_LOG"
    private static let stopProcessAction = "STOP_PROC"

    /// Call once at app launch: delegate, categories, authorization.
    public func setup() {
        center.delegate = self
        let openApp = UNNotificationAction(identifier: Self.openAppAction,
                                           title: "Open Mac Analyzers", options: [.foreground])
        let openLog = UNNotificationAction(identifier: Self.openLogAction,
                                           title: "Open Log", options: [.foreground])
        let stopProc = UNNotificationAction(identifier: Self.stopProcessAction,
                                            title: "Stop Process", options: [.destructive])
        let event = UNNotificationCategory(identifier: Self.eventCategory,
                                           actions: [openApp, openLog],
                                           intentIdentifiers: [], options: [])
        let actionable = UNNotificationCategory(identifier: Self.actionableCategory,
                                                actions: [stopProc, openApp, openLog],
                                                intentIdentifiers: [], options: [])
        center.setNotificationCategories([event, actionable])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Maintenance action: re-ask macOS for notification permission when it's
    /// still undetermined; otherwise report the current state and open the
    /// System Settings pane so the user can flip it themselves (apps cannot
    /// reset their own grant — that lever is deliberately the user's).
    public func reRequestPermission(completion: @escaping @MainActor (String) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .notDetermined:
                    self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in
                            completion(granted ? "Permission granted." : "Permission declined — enable it in System Settings.")
                        }
                    }
                case .denied:
                    completion("Currently denied — opening System Settings so you can re-enable it.")
                    GuardControl.openNotificationSettings()
                default:
                    completion("Already allowed — opening System Settings for style/preview options.")
                    GuardControl.openNotificationSettings()
                }
            }
        }
    }

    public func post(title: String, subtitle: String? = nil, message: String,
                     sound: String?, logPath: String?, pid: Int? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = message
        content.categoryIdentifier = pid == nil ? Self.eventCategory : Self.actionableCategory
        content.threadIdentifier = title
        if let sound, !sound.isEmpty {
            content.sound = sound.lowercased() == "default"
                ? .default
                : UNNotificationSound(named: UNNotificationSoundName(sound + ".aiff"))
        }
        var info: [String: Any] = [:]
        if let logPath { info["log"] = logPath }
        if let pid {
            info["pid"] = pid
            // identity check token so a recycled pid is never killed
            info["token"] = subtitle ?? ""
        }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - click handling helpers

    fileprivate func openApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: NotifyChannel.openSettingsInternal, object: nil)
    }

    /// Verified stop: the pid must still exist AND its command line must
    /// still contain the token from notification time — a recycled pid never
    /// gets a stray signal.
    fileprivate func stopProcess(pid: Int, token: String) {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "args="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        let args = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // token is the short name ("next-server (v16.2.6)") — match its first word
        let needle = token.split(separator: " ").first.map(String.init) ?? token
        guard !args.isEmpty, !needle.isEmpty, args.contains(needle) else {
            post(title: "Mac Analyzers",
                 message: "That process already exited — nothing to stop.",
                 sound: nil, logPath: nil)
            return
        }
        kill(pid_t(pid), SIGTERM)
        post(title: "Mac Analyzers", subtitle: token,
             message: "Stop signal sent (pid \(pid)).",
             sound: nil, logPath: nil)
    }
}

extension NotificationPoster: UNUserNotificationCenterDelegate {

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler done: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let logPath = info["log"] as? String
        let pid = info["pid"] as? Int
        let token = info["token"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor in
            let poster = NotificationPoster.shared
            switch action {
            case Self.openLogAction:
                if let logPath { GuardControl.openLog(URL(fileURLWithPath: logPath)) }
            case Self.stopProcessAction:
                if let pid { poster.stopProcess(pid: pid, token: token) }
            default:
                // body click or "Open Mac Analyzers" → the app, where the
                // actionable buttons live
                poster.openApp()
            }
        }
        done()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        done([.banner, .sound])
    }
}
