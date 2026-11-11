import AnalyzersKit
import AppKit
import SwiftUI

/// What a Storage row's menu offers: Show in Finder and Copy Path for the rows that are real
/// things on disk (a path key; a `prune:` row has none). v2.69.1 had Show in Finder on Caches,
/// Downloads and Temp rows. The shared review table gets a row menu; each Storage screen passes
/// `StorageRowMenu.items(for:in:)` to it, so the table stays one table.
@MainActor
enum StorageRowMenu {

    /// The rows of `ids` that are paths that still exist.
    static func paths(for ids: Set<String>, in rows: StorageRows?) -> [String] {
        guard let rows else { return [] }
        return rows.rows.filter { ids.contains($0.id) && $0.id.hasPrefix("/") && FileManager.default.fileExists(atPath: $0.id) }
            .map(\.id)
    }

    @ViewBuilder static func items(for ids: Set<String>, in rows: StorageRows?) -> some View {
        let found = paths(for: ids, in: rows)
        if !found.isEmpty {
            Button(Names.Review.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting(found.map { URL(fileURLWithPath: $0) })
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(found.joined(separator: "\n"), forType: .string)
            }
        }
    }
}
