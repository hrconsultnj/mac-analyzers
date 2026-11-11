import AnalyzersKit
import SwiftUI

/// Caches & Builds: what can be reclaimed from your projects, app caches and developer tools,
/// as a review you can tick through. Daily looks only at build caches that have not been
/// written to in days; Deep goes further (see `CacheMode`). Everything here is made again the
/// next time it is needed.
struct CachesScreen: View {
    @State private var model = StorageReviewModel()
    @State private var mode: CacheMode = .daily
    @Environment(JobStore.self) private var store
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?

    var body: some View {
        StorageReviewScreen<CacheCategory>(
            model: model, title: Names.Screen.cachesAndBuilds, kind: .storageClean, screenKey: "caches",
            options: mode.options,
            parse: { CacheReview.build(lines: $0.lines, banner: $0.banner).rows },
            lastKnownMatches: { [deep = mode == .deep] in $0.banner.contains("mode=deep") == deep },
            applyTitle: "Remove",
            confirmation: ReviewConfirmation(
                verb: "Remove", destination: "permanently",
                message: "These are caches and builds that are made again the next time they are needed.",
                permanent: "They are deleted, not moved to the Trash, so this can't be undone."),
            emptyText: "Daily: \(CacheMode.daily.sentence) Deep: \(CacheMode.deep.sentence) Nothing is removed until you review it.",
            subtitlePrefix: mode.title)
            .toolbar {
                ToolbarItem {
                    Picker("Cleanup", selection: $mode) {
                        ForEach(CacheMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .help(mode.sentence)
                }
                .toolbarRank(.secondary)
            }
            .onChange(of: mode) { model.discard(store) }
            .onAppear { if let fixture { model.showFixture(fixture) } }
    }
}
