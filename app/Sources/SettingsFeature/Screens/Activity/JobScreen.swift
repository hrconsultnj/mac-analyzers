import SwiftUI
import AnalyzersKit
import UIComponents

/// One job, pushed on Activity's stack: from the toolbar status item, a
/// finish notification (`job:<uuid>`), or a row. The id may belong to this
/// session's store or only to the job index (a notification clicked after a
/// relaunch). An id found in neither shows that plainly: redirecting would
/// put a Back loop in the history.
struct JobScreen: View {
    let id: UUID

    @Environment(JobStore.self) private var store
    private var model: ActivityModel { .shared }

    private var row: ActivityRow? { model.row(forJob: id) }
    private var storeStamp: [JobStamp] { store.jobs.map { JobStamp($0) } }

    var body: some View {
        Group {
            if row != nil {
                ActivityInspector(row: row, model: model)
            } else if model.hasLoaded {
                EmptyState("This Run Is No Longer Recorded", systemImage: "questionmark.folder",
                                       description: Text("It is not in this session, and the list of past runs no longer has it."))
            } else {
                LoadingState()
            }
        }
        .navigationTitle(row?.title ?? "Run")
        .task { await model.refreshIfNeeded(store: store) }
        .onChange(of: storeStamp) { Task { await model.refreshIfNeeded(store: store, maxAge: 0) } }
    }
}
