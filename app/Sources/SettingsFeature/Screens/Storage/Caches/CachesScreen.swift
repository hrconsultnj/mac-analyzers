import AnalyzersKit
import SwiftUI

/// Caches & Builds: what can be reclaimed from your projects, app caches and developer tools,
/// as a review you can tick through. Daily looks only at build caches that have not been
/// written to in days; Deep goes further (see `CacheMode`). Everything here is made again the
/// next time it is needed.
struct CachesScreen: View {
    @State private var model = StorageReviewModel()
    /// The person's own pick for the next preview; nil until they pick. What the screen SHOWS
    /// (`mode`) comes from the preview on screen, because that is what an Apply runs with.
    @State private var chosen: CacheMode?
    @Environment(JobStore.self) private var store
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?

    private var mode: CacheMode {
        CacheMode(options: model.setting(kind: .storageClean, chosen: (chosen ?? .daily).options))
    }

    private var modeBinding: Binding<CacheMode> {
        Binding(get: { mode }, set: { picked in
            if model.pick(picked.options, kind: .storageClean, chosen: (chosen ?? .daily).options, store) { chosen = picked }
        })
    }

    var body: some View {
        let words = model.words(kind: .storageClean, chosen: (chosen ?? .daily).options)
        StorageReviewScreen<CacheCategory>(
            model: model, title: Names.Screen.cachesAndBuilds, kind: .storageClean, screenKey: "caches",
            // a new preview starts with the app's own pick; only SHOWING an existing preview (one made in
            // Terminal, or by the schedule) follows that preview's setting
            options: model.phase == .lastKnown ? (chosen ?? .daily).options : mode.options,
            parse: { CacheReview.build(lines: $0.lines, banner: $0.banner).rows },
            // before the person picks, the newest logged preview of either mode; after, only that mode's
            lastKnownMatches: { [picked = chosen] block in
                picked.map { StorageSetting.options(kind: .storageClean, banner: block.banner) == $0.options } ?? true
            },
            applyTitle: words.applyTitle,
            confirmation: ReviewConfirmation(words: words),
            emptyText: "Daily: \(CacheMode.daily.sentence) Deep: \(CacheMode.deep.sentence) Nothing is removed until you review it.",
            subtitlePrefix: mode.title, destination: Names.Review.deletedPermanently)
            .toolbar {
                ToolbarItem {
                    // a menu whose label is the current choice, icon and title: the value is always in view
                    Menu {
                        Picker("Cleanup", selection: modeBinding) {
                            ForEach(CacheMode.allCases) { Label($0.title, systemImage: Self.symbol($0)).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(mode.title, systemImage: Self.symbol(mode))
                    }
                    .labelStyle(.titleAndIcon)
                    .help(mode.sentence)
                }
                .toolbarRank(.primary)
            }
            .onAppear { if let fixture { model.showFixture(fixture) } }
    }

    private static func symbol(_ mode: CacheMode) -> String { mode == .deep ? "square.stack.3d.down.right" : "calendar" }
}
