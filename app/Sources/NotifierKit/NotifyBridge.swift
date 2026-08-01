import Foundation
import AnalyzersKit

/// Receives notification requests from the bash scripts via the bundled CLI
/// shim (DistributedNotificationCenter — the claude-notify pattern). The CLI
/// posts {title, message, sound, log} as userInfo; we forward to the poster.
@MainActor
public enum NotifyBridge {

    private static var observer: NSObjectProtocol?

    public static func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(NotifyChannel.name),
            object: nil,
            queue: .main
        ) { note in
            // extract only Sendable bits inside the nonisolated block,
            // then hop to the main actor
            let info = note.userInfo
            let title = info?["title"] as? String ?? "Mac Analyzers"
            let subtitle = info?["subtitle"] as? String
            let message = info?["message"] as? String ?? ""
            let sound = info?["sound"] as? String
            let log = info?["log"] as? String
            guard !message.isEmpty else { return }
            Task { @MainActor in
                NotificationPoster.shared.post(title: title, subtitle: subtitle,
                                               message: message, sound: sound, logPath: log)
            }
        }
    }
}
