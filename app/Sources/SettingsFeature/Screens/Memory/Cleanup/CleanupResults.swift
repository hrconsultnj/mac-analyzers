import AnalyzersKit
import SwiftUI

/// A finished cleanup's results, in the same categories and groups as the cleanup's own
/// screen: a tab per kind of thing, rows under the app or project they belong to, what
/// became of each as its detail. Used by Memory Cleanup after an apply, and by the run's
/// own screen (`SidebarGroup.runResults`) for both cleanups.
struct CleanupResultsView: View {
    let review: CleanupReview
    let screen: String
    /// A line under the summary (what the run did in one sentence).
    var note: String?

    @State private var session: ReviewSession
    @State private var tabs: CleanupTabs
    @State private var tab = CleanupTab.other

    init(review: CleanupReview, screen: String, note: String? = nil) {
        self.review = review
        self.screen = screen
        self.note = note
        _session = State(initialValue: ReviewSession(readOnly: review.resultRows()))
        _tabs = State(initialValue: CleanupTabs(review))
    }

    var body: some View {
        let current = tabs.items.contains { $0.value == tab } ? tab : (tabs.items.first?.value ?? tab)
        ReviewTable(session: session, readOnly: true, note: note ?? review.protectedNote,
                    only: tabs.hasTabs ? tabs.rowIDs[current] : nil)
            .modifier(CleanupTabsModifier(tabs: tabs, screen: screen, selection: $tab))
    }
}

/// The run screen's results for a cleanup run: read from the job the app ran, or from the
/// log block of a run it did not start.
struct CleanupRunResults: View {
    let row: ActivityRow
    @Environment(JobStore.self) private var store
    @State private var review: CleanupReview?
    @State private var looked = false

    var body: some View {
        Group {
            if let review {
                CleanupResultsView(review: review, screen: "run.\(row.kind?.rawValue ?? "memoryClean")")
            } else if looked {
                ContentUnavailableView("No Details Were Recorded", systemImage: "text.alignleft",
                                       description: Text("Show Raw Output has the text this run left."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: row.id) { await load() }
    }

    private func load() async {
        if let jobID = row.jobID, let job = store.jobs.first(where: { $0.id == jobID }),
           case .succeeded(let outcome) = job.state, case .reap(let run) = outcome.parsed {
            review = CleanupReview(run: run)
        } else if case .logged(let log, let header, let ordinal) = row.source {
            let reference = RunReference(log: log, header: header, ordinal: ordinal)
            let found = await Task.detached(priority: .userInitiated) { () -> CleanupReview? in
                guard let run = reference.resolve(in: LogParser.runs(for: log)) else { return nil }
                return CleanupReview(run: ReapParser.parse(runHeader: run.header, lines: run.lines))
            }.value
            review = found
        }
        looked = true
    }
}
