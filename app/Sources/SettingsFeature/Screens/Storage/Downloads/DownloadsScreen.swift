import AnalyzersKit
import SwiftUI

/// Downloads: files and screenshots that have sat untouched past your limit, by kind of file,
/// each group an age. Everything goes to the Trash, so it can be put back from Undo.
struct DownloadsScreen: View {
    @State private var model = StorageReviewModel()
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?

    var body: some View {
        StorageReviewScreen<DownloadCategory>(
            model: model, title: Names.Screen.downloads, kind: .janitor, screenKey: "downloads",
            options: JobOptions(),
            parse: { DownloadReview.build(lines: $0.lines).rows },
            applyTitle: "Move to Trash",
            confirmation: ReviewConfirmation(
                verb: "Move", destination: "to the Trash",
                message: "You can put them back from Undo.", permanent: nil),
            emptyText: "Looks through your Downloads folder and your screenshots for anything not touched in a while. Nothing is moved until you review it.",
            destination: Names.Review.goesToTrash)
            .onAppear { if let fixture { model.showFixture(fixture) } }
    }
}
