import Foundation
import AnalyzersKit

/// Receives notification requests from the bash scripts via the bundled CLI
/// shim (DistributedNotificationCenter — the claude-notify pattern). The CLI
/// posts {title, message, sound, log} as userInfo; we forward to the poster.
@MainActor
public enum NotifyBridge {

    private static var observers: [NSObjectProtocol] = []

    public static func start() {
        guard observers.isEmpty else { return }
        for name in [NotifyChannel.name, NotifyChannel.legacyName] {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { note in
                // extract only Sendable bits inside the nonisolated block,
                // then hop to the main actor
                let info = note.userInfo
                let title = info?["title"] as? String ?? AppIdentity.productName
                let subtitle = info?["subtitle"] as? String
                let message = info?["message"] as? String ?? ""
                let sound = info?["sound"] as? String
                let log = info?["log"] as? String
                let pid = (info?["pid"] as? String).flatMap(Int.init)
                guard !message.isEmpty else { return }
                Task { @MainActor in
                    NotificationPoster.shared.post(title: title, subtitle: subtitle,
                                                   message: message, sound: sound,
                                                   logPath: log, pid: pid)
                }
            }
            observers.append(token)
        }
        // ProKit still posts the old open-pane name. Forward it in-process.
        for name in [NotifyChannel.legacyOpenPane, NotifyChannel.legacyOpenSettings] {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { note in
                let target = note.userInfo?["target"] as? String
                Task { @MainActor in
                    SettingsOpener.open(target: target)
                }
            }
            observers.append(token)
        }
    }
}
