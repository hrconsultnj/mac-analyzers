import SwiftUI
import AnalyzersKit
import NotifierKit
import MenuBarFeature
import SettingsFeature

/// Invisible view that turns the internal open-settings signal into an
/// actual openSettings() call (with the activation dance already done by
/// the poster of the signal).
struct SettingsAnchorView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(
                for: NotifyChannel.openSettingsInternal)) { _ in
                SettingsOpener.markHandled(by: "anchor-window")
                openSettings()
            }
    }
}

/// The status-bar chip. It ALSO hosts the open-settings receiver: os_log
/// diagnosis (2026-08-01) showed the hidden 1×1 anchor window's publisher
/// gets suspended with the window occluded, so Dock-click reopens died
/// silently. The label is the one render tree that is alive and visible
/// for the app's entire lifetime — its receiver always fires.
struct MenuBarLabelView: View {
    let killsToday: Int
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let icon = MacAnalyzersApp.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "memorychip")
            }
            if killsToday > 0 {
                Text("\(killsToday)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NotifyChannel.openSettingsInternal)) { _ in
            SettingsOpener.markHandled(by: "menu-bar-label")
            openSettings()
        }
    }
}

@main
struct MacAnalyzersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = GuardLogStore()
    @State private var config = ConfigStore()

    /// Brand chip glyph from Contents/Resources (hand-copied by build.sh —
    /// deliberately Bundle.main, not Bundle.module; see research on SPM
    /// resource-bundle placement in assembled .apps).
    static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(store)
                .environment(config)
                .frame(width: 420)
        } label: {
            // brand chip glyph as a TEMPLATE image (black+alpha, macOS tints
            // it for light/dark/translucency); SF-symbol fallback if missing.
            // The badge is the count of today's kills.
            MenuBarLabelView(killsToday: store.killsToday)
        }
        .menuBarExtraStyle(.window)

        // Hidden 1×1 anchor window declared BEFORE Settings: gives SwiftUI a
        // live render tree so openSettings() works from a MenuBarExtra-only
        // app (Steinberger workaround — still required on Tahoe). It also
        // owns the internal open-settings signal (Dock click, notification
        // default action) since it holds the environment action.
        WindowGroup(id: "settings-anchor") {
            SettingsAnchorView()
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        Settings {
            SettingsTabsView()
                .environment(store)
                .environment(config)
        }
    }
}
