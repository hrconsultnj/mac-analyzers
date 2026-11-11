import AppKit
import AnalyzersKit
import os
import ServiceManagement

/// Registering the app as a login item.
extension AppDelegate {

    func registerLoginItem() {
        // Self-register as a Login Item (macOS notifies the user it was
        // added, with a link to System Settings — the transparent, Apple-
        // sanctioned path). Idempotent: skip when already enabled; if the
        // user removes it in System Settings, macOS remembers the opt-out.
        //
        // One-time migration: when first launched from /Applications (the
        // canonical install), re-register so the login item points here and
        // not at the repo build-artifact copy.
        let inApplications = Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        let migratedKey = "loginItemMovedToApplications"
        //
        // Failures are recorded rather than swallowed: the Setup screen reads
        // the live status and says what went wrong, instead of the app quietly
        // not opening at login forever.
        do {
            if inApplications, !UserDefaults.standard.bool(forKey: migratedKey) {
                try? SMAppService.mainApp.unregister()
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: migratedKey)
            } else if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            Self.log.error("login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
