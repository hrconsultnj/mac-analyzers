import SwiftUI
import AnalyzersKit

/// One run found in an engine log, pushed on the stack (`Route.run`): a block
/// the schedule, the guard or Terminal wrote, which nothing in this app
/// tracked. The same screen as a tracked job's, built from the log's own words.
struct RunScreen: View {

    /// Which run: one a route named exactly, or the newest of a log (a deep link
    /// asks for that by log, and the lookup happens here, not in the resolver).
    enum Subject { case reference(RunReference), newest(EngineLog?) }

    let subject: Subject

    init(reference: RunReference) { subject = .reference(reference) }
    init(newestIn log: EngineLog?) { subject = .newest(log) }

    @Environment(JobStore.self) private var store
    private var model: ActivityModel { .shared }

    private var row: ActivityRow? {
        switch subject {
        case .reference(let reference):
            return model.row(for: reference)
        case .newest(let log):
            return model.rows.filter {
                if case .logged = $0.source { return $0.log == log }
                return false
            }.max { ($0.started ?? .distantPast) < ($1.started ?? .distantPast) }
        }
    }

    var body: some View {
        Group {
            if row != nil {
                ActivityInspector(row: row, model: model)
            } else if model.hasLoaded {
                ContentUnavailableView("This Run Is No Longer Recorded", systemImage: "questionmark.folder",
                                       description: Text("The log has moved on since this entry was listed."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(row?.title ?? "Run")
        .task { await model.refreshIfNeeded(store: store) }
    }
}
