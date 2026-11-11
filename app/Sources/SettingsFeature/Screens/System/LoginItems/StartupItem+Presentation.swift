import AppKit
import AnalyzersKit
import SwiftUI

/// How a startup item looks: the app's own icon when its app is installed,
/// otherwise a symbol for its kind.
extension StartupItem {

    var symbol: String {
        switch kind {
        case .loginItem: "person.crop.circle"
        case .launchAgent: "gearshape"
        case .launchDaemon: "gearshape.2"
        case .helperTool: "wrench.and.screwdriver"
        }
    }

    /// The icon of the app it belongs to, when that app exists on disk.
    var appIcon: NSImage? {
        guard let appPath, FileManager.default.fileExists(atPath: appPath) else { return nil }
        return NSWorkspace.shared.icon(forFile: appPath)
    }

    /// Orange for something worth a look, secondary for the rest.
    var findingStyle: HierarchicalShapeStyle { .secondary }

    var findingColor: Color? {
        switch finding {
        case .leftover: .red
        case .possibleLeftover: .orange
        default: nil
        }
    }

    // sort keys: a KeyPathComparator needs a plain Comparable property
    var kindTitle: String { kind.title }
    var administratorTitle: String { needsAdministrator ? "Yes" : "No" }
    var findingRank: Int { finding.rank }
}

/// An item's icon: its app's own when the app is installed, otherwise a symbol
/// for its kind.
struct StartupIcon: View {
    let item: StartupItem

    var body: some View {
        if let icon = item.appIcon {
            // an app icon is drawn at its own size: that is its job
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
        } else {
            // symbols differ in width; a fixed icon size keeps the names aligned
            Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 16, height: 16)
        }
    }
}
