import SwiftUI
import AnalyzersKit
import UIComponents

/// One job, pushed on Activity's stack: from the toolbar status item, a
/// finish notification (`job:<uuid>`), or a row's context menu. The same
/// panel the inspector shows, given the whole window.
///
/// The id may belong to this session's store or only to the job index (a
/// notification clicked after a relaunch). An id found in neither lands the
/// user on Activity's root instead of an empty page.
struct JobScreen: View {
    let id: UUID

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var model = ActivityModel()
    @State private var missing = false

    private var row: ActivityRow? { model.row(forJob: id) }
    private var storeStamp: [JobStamp] { store.jobs.map { JobStamp($0) } }

    var body: some View {
        Group {
            if row != nil {
                ActivityInspector(row: row, model: model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(row?.title ?? "Job")
        .task { await load() }
        .onChange(of: storeStamp) { Task { await model.refresh(store: store) } }
    }

    private func load() async {
        await model.refresh(store: store)
        if model.row(forJob: id) == nil {
            // not in the store, not in the index: nothing to show here
            navigator.open(Location(OverviewGroup.activity))
        }
    }
}
