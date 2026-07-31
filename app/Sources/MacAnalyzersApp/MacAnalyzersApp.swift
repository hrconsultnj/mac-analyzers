import SwiftUI
import AnalyzersKit
import NotifierKit
import MenuBarFeature
import SettingsFeature

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
                .frame(width: 360)
        } label: {
            // brand chip glyph as a TEMPLATE image (black+alpha, macOS tints
            // it for light/dark/translucency); SF-symbol fallback if missing.
            // The badge is the count of today's kills.
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "memorychip")
            }
            if store.killsToday > 0 {
                Text("\(store.killsToday)")
            }
        }
        .menuBarExtraStyle(.window)

        // Hidden 1×1 anchor window declared BEFORE Settings: gives SwiftUI a
        // live render tree so openSettings() works from a MenuBarExtra-only
        // app (Steinberger workaround — still required on Tahoe).
        WindowGroup(id: "settings-anchor") {
            Color.clear.frame(width: 1, height: 1)
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
