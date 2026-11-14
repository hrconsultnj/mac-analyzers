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
///
/// This file is the posting side. Clicks are handled next to it:
///   NotificationPoster+Delegate.swift   Open Log, Stop Process, body click
@MainActor
public final class NotificationPoster: NSObject {

    public static let shared = NotificationPoster()

    private let center = UNUserNotificationCenter.current()
    private static let eventCategory = "MA_EVENT"
    private static let actionableCategory = "MA_ACTIONABLE"
    private static let openAppAction = "OPEN_APP"
    static let openLogAction = "OPEN_LOG"
    static let stopProcessAction = "STOP_PROC"

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
        // Deliberately no permission request here. Asking in the first second
        // after install, before anything has been explained, is the prompt
        // people reflexively decline — and macOS only asks once. The Setup
        // screen asks in context; posting falls back to asking if it must.
    }

    /// Maintenance action: re-ask macOS for notification permission when it's
    /// still undetermined; otherwise report the current state and open the
    /// System Settings pane so the user can flip it themselves (apps cannot
    /// reset their own grant — that lever is deliberately the user's).
    public func reRequestPermission(completion: @escaping @MainActor (String) -> Void) {
        // The async forms of the UserNotifications calls, awaited from the
        // main actor: the center and the request never cross into a
        // @Sendable completion handler.
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                completion(granted ? "Permission granted." : "Permission declined — enable it in System Settings.")
            case .denied:
                completion("Currently denied — opening System Settings so you can re-enable it.")
                GuardControl.openNotificationSettings()
            default:
                completion("Already allowed — opening System Settings for style/preview options.")
                GuardControl.openNotificationSettings()
            }
        }
    }

    public func post(title: String, subtitle: String? = nil, message: String,
                     sound: String?, logPath: String?, pid: Int? = nil,
                     paneTarget: String? = nil) {
        // A notification with a Stop button is about a process that is running now. Its name
        // is the live process's own and its start time is read from the kernel here, never taken
        // from the sender's words: anything in the session can send this app a notification.
        var pid = pid
        var subtitle = subtitle
        var born: ProcessTree.Birth?
        if let wanted = pid {
            if let live = LiveStats.process(pid: wanted), let identity = live.identity {
                subtitle = live.friendlyName
                born = identity.birth
            } else {
                pid = nil
            }
        }
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
        if let paneTarget { info["pane"] = paneTarget }
        if let pid {
            info["pid"] = pid
            // when the process started (the kernel's own reading): the click stops it only if that is still true
            if let born { info["start"] = born.seconds; info["startMicro"] = born.microseconds }
        }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        // Safety net for anyone who never opens Setup: the first thing worth
        // announcing is also a fine moment to ask.
        // Declining the prompt still falls through to `add`, as before; for a
        // user who declined, macOS simply does not show it.
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    /// A job ended. Posted only when the main window is not the key window —
    /// someone looking at it already sees the result in the status item. A click
    /// opens `job:<uuid>` in Activity (the same pane-target path every
    /// notification uses).
    public func postJobFinished(id: UUID, task: String, result: String, failed: Bool) {
        guard !Self.mainWindowIsKey else { return }
        post(title: "Mac Analyzers",
             subtitle: failed ? "\(task) didn't finish" : "\(task) finished",
             message: result, sound: nil, logPath: nil,
             paneTarget: "job:\(id.uuidString)")
    }

    /// The main window is on screen, in front, and the app is active.
    private static var mainWindowIsKey: Bool {
        guard NSApp.isActive, let key = NSApp.keyWindow else { return false }
        return key.identifier?.rawValue.lowercased().contains("main") ?? false
    }

    // MARK: - click handling helpers

    func openApp() {
        SettingsOpener.open()
    }

    /// The notification's Stop Process. It goes through the same rules as every other stop:
    /// the process must be the one that was running when the notification was posted (its start
    /// time, read from the kernel then), a live coding session or something hosting one is never
    /// stopped, and with no list of coding agents nothing is. When the rules refuse, or the process
    /// is not the one that was reported, the click opens Monitor on that process with the reason (a code the
    /// app turns into its own sentence): a notification always leads somewhere a person can act, and
    /// never acts past the rules.
    func stopProcess(pid: Int, start: Int?, startMicro: Int?) {
        guard let live = LiveStats.process(pid: pid) else {
            post(title: "Mac Analyzers", message: "That process already exited — nothing to stop.",
                 sound: nil, logPath: nil)
            return
        }
        guard let start, let startMicro, let identity = live.identity,
              identity.birth.seconds == start, identity.birth.microseconds == startMicro else {
            // an older notification that carries no start time, or a pid that now belongs to another process
            let why: StopWhy = start == nil ? .unverifiable : .changed
            SettingsOpener.open(target: why.target(pid: pid))
            return
        }
        switch GuardControl.stopProcess(live, identity: identity) {
        case .stopped:
            post(title: "Mac Analyzers", subtitle: live.friendlyName,
                 message: "Asked \(live.friendlyName) to stop (process \(pid)).",
                 sound: nil, logPath: nil)
        case .gone:
            post(title: "Mac Analyzers", message: "That process already exited — nothing to stop.",
                 sound: nil, logPath: nil)
        case .refused:
            SettingsOpener.open(target: StopWhy.after(refusedPID: pid).target(pid: pid))
        }
    }
}
