import AnalyzersKit
import SwiftUI

/// Unused Apps: apps you have not opened for months, each with what goes with it (its Application
/// Support, Caches, Preferences and the like). Tick the ones to remove, then Remove. The app removes
/// exactly the ticked apps' bundles and their footprints, from the reviewed list, and nothing else.
struct UnusedAppsScreen: View {
    @State private var model = StorageReviewModel()
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?

    var body: some View {
        StorageReviewScreen<UnusedAppCategory>(
            model: model, title: Names.Screen.unusedApps, kind: .unusedApps, screenKey: "unusedapps",
            options: JobOptions(),
            parse: { UnusedReview.apps(lines: $0.lines) },
            applyTitle: "Move to Trash",
            confirmation: ReviewConfirmation(
                verb: "Move", destination: "to the Trash",
                message: "Each app goes to the Trash together with its settings, caches and saved data (listed under each app). You can put them back from Undo, and the space returns when the Trash is emptied.",
                permanent: nil, namesRows: "Apps to remove"),
            emptyText: "Looks through your Applications folders for apps you have not opened for six months or more. Nothing is removed until you review it.",
            destination: Names.Review.goesToTrash)
            .onAppear { if let fixture { model.showFixture(fixture) } }
    }
}
