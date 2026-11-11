import AppKit
import ApplicationServices
import Foundation

/// Whether Mac Analyzers may ask System Events about login items, found out
/// WITHOUT letting macOS ask: opening a screen must never raise a permission
/// prompt. The prompt appears only when a person presses Audit.
public enum SystemEventsPermission: Sendable {
    case granted, undetermined, denied

    /// The answer without blocking a cooperative thread: the check can wait for
    /// System Events to start, which takes seconds, so it runs on a thread of its own.
    public static func currentOffPool() async -> SystemEventsPermission {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: current()) }
        }
    }

    /// Blocking (it may start System Events): call it off the main actor.
    public static func current() -> SystemEventsPermission {
        var status = ask()
        if status == OSStatus(procNotFound) {
            // System Events is a background app and is usually not running; the
            // question can only be put to a running app. Starting it asks nothing.
            startSystemEvents()
            status = ask()
        }
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .undetermined
        }
    }

    private static func ask() -> OSStatus {
        var target = AEAddressDesc()
        let bundle = "com.apple.systemevents"
        let created = bundle.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &target) }
        guard created == noErr else { return OSStatus(errAEEventWouldRequireUserConsent) }
        defer { AEDisposeDesc(&target) }
        // askUserIfNeeded false: report, never prompt
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard),
                                                     AEEventID(typeWildCard), false)
    }

    private static func startSystemEvents() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systemevents") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 3)
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// The sentence for the screen when an audit would need to ask.
    public var sentence: String? {
        switch self {
        case .granted: nil
        case .undetermined: "Checking login items needs permission to ask System Events. macOS will ask when you press Audit."
        case .denied: "macOS has turned off permission for Mac Analyzers to ask System Events, so login items can't be checked. Turn it on in System Settings, under Privacy & Security, Automation, then audit again."
        }
    }
}
