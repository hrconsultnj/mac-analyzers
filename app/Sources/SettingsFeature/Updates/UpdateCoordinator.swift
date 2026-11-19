import AppKit
import AnalyzersKit

/// "Check for Updates…", the command in the app menu and in Help. It installs the channel that is picked:
/// the latest release, the latest beta, or a rebuild of Development. When that is already what is running,
/// it says so. When GitHub cannot be reached and there is nothing to install, it says so.
@MainActor
public final class UpdateCoordinator {
    public static let shared = UpdateCoordinator()
    private weak var updates: UpdateState?

    /// The app hands over its one update state when its menu-bar label starts.
    public func attach(_ state: UpdateState) { updates = state }

    var isReady: Bool { updates != nil }

    func checkForUpdates() async {
        guard let updates else { return }
        await updates.check(force: true)
        await present(for: updates)
    }

    private func present(for updates: UpdateState) async {
        NSApp.activate()
        if updates.reachedGitHub == false, !updates.offersInstall {
            UpdateAlerts.unreachable().runModal()
            return
        }
        // The channel that is picked is what gets installed: the release, the beta, or Development.
        if updates.offersInstall {
            updates.requestInstall()
            return
        }
        UpdateAlerts.upToDate(updates: updates).runModal()
    }
}

/// The alerts, built apart from being shown so a render can draw them.
@MainActor
public enum UpdateAlerts {
    public static func upToDate(updates: UpdateState) -> NSAlert {
        let alert = base(title: Names.Update.upToDate,
                         text: updates.build.isDevelopment ? updates.statusDetail : Names.Update.newestVersion(updates.build.label))
        alert.addButton(withTitle: "OK")
        return alert
    }

    public static func unreachable() -> NSAlert {
        let alert = base(title: Names.Update.cantReach, text: Names.Update.cantReachDetail)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        return alert
    }

    public static func cloneNewer(rebuildTitle: String) -> NSAlert {
        let alert = base(title: Names.Update.cloneNewer, text: Names.Update.rebuildQuestion)
        alert.addButton(withTitle: rebuildTitle)
        alert.addButton(withTitle: "Not Now")
        return alert
    }

    /// A picture of the alert of `kind` ("up-to-date", "unreachable", "clone") drawn from its own views, for `snapshot-runner`:
    /// the alert is laid out and drawn into a bitmap on the window's own background and is never shown.
    public static func picture(kind: String, updates: UpdateState, dark: Bool) -> Data? {
        let alert: NSAlert = switch kind {
        case "unreachable": unreachable()
        case "clone": cloneNewer(rebuildTitle: Names.Channel.rebuild)
        default: upToDate(updates: updates)
        }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        alert.window.appearance = appearance
        alert.layout()
        guard let view = alert.window.contentView?.superview ?? alert.window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // the window's own background, which a view alone does not paint, in the alert's appearance
        (appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
            view.displayIgnoringOpacity(view.bounds, in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func base(title: String, text: String) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = title
        alert.informativeText = text
        return alert
    }
}
