import AppKit
import Foundation

/// The icon of an app, tool or service group, wherever it can be found.
///
/// `NSRunningApplication.icon` only knows applications registered with the system, and the process that stands
/// for a group is often one that is not (OrbStack's is a helper tool inside its bundle), so a group read as
/// iconless. The enclosing `.app` bundle of a process's executable always has the icon: for an app, that is
/// asked first. A bare command-line tool has no bundle and gets nothing here; the caller draws its category's
/// symbol.
@MainActor
public enum GroupIcon {

    private static var bundleIcons: [String: NSImage] = [:]

    public static func image(for group: CensusGroup) -> NSImage? {
        // an app: the outermost bundle its executable sits in is the app itself (a helper's own bundle is nested in it)
        if group.category == .apps {
            for process in [group.lead] + group.members.prefix(8) {
                if let bundle = outermostBundle(ofPID: process.pid) { return icon(ofBundle: bundle) }
            }
        }
        for process in [group.lead] + group.members.prefix(8) {
            if let image = NSRunningApplication(processIdentifier: pid_t(process.pid))?.icon { return image }
        }
        return nil
    }

    /// The icon for one process that stands for an app (Monitor's rows carry the pid): its bundle's, else the running
    /// application's.
    public static func image(forAppPID pid: Int) -> NSImage? {
        if let bundle = outermostBundle(ofPID: pid), let image = icon(ofBundle: bundle) { return image }
        return NSRunningApplication(processIdentifier: pid_t(pid))?.icon
    }

    /// `/Applications/OrbStack.app` for any executable inside it, however deep.
    static func outermostBundle(ofPID pid: Int) -> String? {
        let path = ProcTable.executablePath(of: Int32(pid))
        return outermostBundle(inPath: path)
    }

    public static func outermostBundle(inPath path: String) -> String? {
        var parts: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            parts.append(String(component))
            if component.hasSuffix(".app") { return "/" + parts.joined(separator: "/") }
        }
        return nil
    }

    private static func icon(ofBundle path: String) -> NSImage? {
        if let cached = bundleIcons[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        bundleIcons[path] = image
        return image
    }
}
