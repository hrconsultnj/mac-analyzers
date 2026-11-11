import AnalyzersKit
import AppKit
import SwiftUI

/// What a screen offers on a row of the shared review table: the items for the row that was
/// right-clicked, or for the whole selection when that row is in it (AppKit's rule). Items act on
/// the rows; they never change a tick, and a right-click only selects. The table is the one table:
/// a screen that wants "Show in Finder" on its rows passes `ReviewRowMenu.files` here and never builds
/// a second table for it.
///
///     ReviewTable(session: session, …, rowMenu: .files)
///     ReviewTable(session: session, …, rowMenu: ReviewRowMenu { rows in Button("Quit") { … } })
struct ReviewRowMenu {
    /// The items for these rows: the review's own rows, in review order, never a group's line or the
    /// fold's (a group is not a thing the engine listed).
    let items: @MainActor ([ReviewRow]) -> AnyView

    init<Items: View>(@ViewBuilder _ items: @escaping @MainActor ([ReviewRow]) -> Items) {
        self.items = { AnyView(items($0)) }
    }

    /// Show in Finder and Copy Path for rows whose key is a file path (every file review).
    static var files: ReviewRowMenu { ReviewRowMenu { ReviewFileItems(rows: $0) } }
}

/// Show in Finder and Copy Path(s): the rows whose key is an absolute path.
struct ReviewFileItems: View {
    let rows: [ReviewRow]

    private var paths: [String] { rows.map(\.id).filter { $0.hasPrefix("/") } }

    var body: some View {
        if !paths.isEmpty {
            Button(Names.Review.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
            }
            Button(paths.count == 1 ? Names.Review.copyPath : Names.Review.copyPaths) { Self.copy(paths) }
        }
    }

    /// One pasteboard item per path, each carrying the file itself and its path as text, the way
    /// Finder copies: a path with a line break in its name stays ONE item and is never split into
    /// two. (Pasted as text, several items arrive one per line.)
    static func copy(_ paths: [String], to pasteboard: NSPasteboard = .general) {
        let items = paths.map { path -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
            item.setString(path, forType: .string)
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
