import AppKit
import SwiftUI
import AnalyzersKit

/// "Check for Updates…", the command in the app menu and in Help: the app's ONE update state looks now, and the answer is
/// one of three things a person sees:
/// - up to date: the system's alert, "You're up to date!";
/// - something newer: the update window (the notes of every version in between; Skip This Version, Remind Me Later,
///   Install Update, which runs the same install path as the Updates screen's button and still asks first);
/// - GitHub could not be reached: an alert that says so.
/// On This Copy a newer clone is a rebuild, not a version: its own alert.
@MainActor
public final class UpdateCoordinator {
    public static let shared = UpdateCoordinator()
    private weak var updates: UpdateState?
    private var window: NSWindow?

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
        if updates.reachedGitHub == false {
            UpdateAlerts.unreachable().runModal()
            return
        }
        if let offered = updates.offered {
            let notes = await updates.notesForOffered()
            show(offered: offered, installed: updates.build.label, notes: notes, updates: updates)
            return
        }
        if updates.channel == .thisCopy, updates.isAvailable {
            let alert = UpdateAlerts.cloneNewer(rebuildTitle: Names.Channel.rebuild)
            if alert.runModal() == .alertFirstButtonReturn { updates.requestInstall() }
            return
        }
        UpdateAlerts.upToDate(updates: updates).runModal()
    }

    private func show(offered: UpdateState.Offered, installed: String, notes: [ReleaseNote], updates: UpdateState) {
        window?.close()
        let view = UpdateAvailableView(
            offered: offered.label, installed: installed, notes: notes,
            skip: { [weak self] in UpdateChoices.skip(offered.version); self?.close() },
            remindLater: { [weak self] in UpdateChoices.remindLater(); self?.close() },
            install: { [weak self] in self?.close(); updates.requestInstall() })
        let panel = NSWindow(contentViewController: NSHostingController(rootView: view))
        panel.title = Names.Update.windowTitle
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    private func close() {
        window?.close()
        window = nil
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
