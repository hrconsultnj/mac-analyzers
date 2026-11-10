import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Review of the storage cleaners (Storage Clean, Janitor): items grouped by
/// project, one selectable row per path with its icon and Show in Finder.
extension ActionsSettingsView {

    struct ReviewGroup {
        let project: String
        let items: [StoragePathItem]
        let total: Int64
    }

    func reviewGroups(from run: StorageCleanRun) -> [ReviewGroup] {
        let visible = run.items.filter {
            $0.status == .dry || $0.status == .deleted || $0.status == .trashed
        }
        var groups = Dictionary(grouping: visible, by: \.project).map { key, value in
            let items: [StoragePathItem]
            if sortByName {
                items = value.sorted {
                    $0.cacheKind.localizedCaseInsensitiveCompare($1.cacheKind) == .orderedAscending
                }
            } else {
                items = value.sorted { $0.sizeBytes > $1.sizeBytes }
            }
            return ReviewGroup(project: key, items: items,
                               total: value.map(\.sizeBytes).reduce(0, +))
        }
        if sortByName {
            groups.sort {
                $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
            }
        } else {
            groups.sort { $0.total > $1.total }
        }
        return groups
    }

    // MARK: - path rows (icons + Finder reveal)

    /// Real file/folder icon + Show in Finder — the same first-class
    /// treatment the memory lists give apps.
    func pathRow(_ item: StoragePathItem) -> some View {
        let exists = FileManager.default.fileExists(atPath: item.path)
        return HStack(spacing: 6) {
            DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                     title: item.cacheKind,
                     subtitle: item.path,
                     trailing: ByteSize.format(item.sizeBytes),
                     badge: item.status == .deleted ? ("DELETED", .red)
                         : item.status == .trashed ? ("TRASHED", .orange)
                         : ("WOULD REMOVE", .blue))
            if exists {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: item.path)])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
        }
    }
}
