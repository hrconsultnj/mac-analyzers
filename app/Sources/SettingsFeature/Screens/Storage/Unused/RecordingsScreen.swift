import AnalyzersKit
import SwiftUI

/// Old Recordings: screen and call recordings older than your limit, by the month they were made.
/// The recordings folder is set in config.local.sh; with none set the preview says so.
struct RecordingsScreen: View {
    @State private var model = StorageReviewModel()
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?

    var body: some View {
        StorageReviewScreen<RecordingCategory>(
            model: model, title: Names.Screen.oldRecordings, kind: .recordings, screenKey: "recordings",
            options: JobOptions(),
            parse: { UnusedReview.recordings(lines: $0.lines) },
            applyTitle: "Remove",
            confirmation: ReviewConfirmation(
                verb: "Remove", destination: "permanently",
                message: "These recording folders are older than 90 days.",
                permanent: "They are deleted, not moved to the Trash, so this can't be undone."),
            emptyText: "Looks through the folder you keep recordings in for ones older than 90 days. Nothing is removed until you review it.",
            destination: Names.Review.deletedPermanently)
            .onAppear { if let fixture { model.showFixture(fixture) } }
    }
}
