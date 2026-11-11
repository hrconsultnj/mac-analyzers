import SwiftUI
import AnalyzersKit
import UIComponents

/// Activity: everything that ran, whoever started it, as a history to read
/// top to bottom — "Running now" first, then one collapsible section per day,
/// then the tasks that have never run. A row is a run named for people; one
/// click opens that run's own screen on the navigation stack.
///
/// One job per file next to it:
///   ActivityFilter.swift          scope, search and which days are open, for the session
///   ActivityModel.swift           the rows (joined from the store, the index and the logs) and their sections
///   ActivityRowView.swift         one row
///   ActivityDaySection.swift      a day's header (collapsible, with its total) and its rows
///   Shared/ScopeTabs.swift        the All / Running / Needs Review / Failed tabs (the app-wide control)
///   ActivityRow+Presentation.swift  glyph, time, and where a row leads
///   ActivityInspector.swift       the run screen: outcome, Stop, live output, raw output
///   JobScreen.swift, RunScreen.swift  the pushed screens for `Route.job` and `Route.run`
///   JobStatusToolbarItem.swift    the shell's status item
///   JobFinishNotifier.swift       the notification when a job ends behind a closed window
///   AnalyzersKit/Activity/        the join, the day grouping and the outcome lists, so the probe can print them
struct ActivityView: View {

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    private var model: ActivityModel { .shared }
    @State private var selection: ActivityRow.ID?
    @FocusState private var searchFocused: Bool
    @Bindable private var filter = ActivityFilter.shared

    /// Changes only when a job moves between queued, running and finished.
    private var storeStamp: [JobStamp] { store.jobs.map { JobStamp($0) } }

    var body: some View {
        let sections = model.sections(scope: filter.scope, query: filter.query)
        let now = Date()
        let actions = RunRowActions(store: store, navigator: navigator, model: model)
        DataScreen(title: Names.Screen.activity, subtitle: subtitle) {
            List(selection: $selection) {
                if !sections.running.isEmpty {
                    Section("Running Now") {
                        ForEach(sections.running) { row in actions.rowView(row, now: now) }
                    }
                }
                RunHistoryList(scope: filter.scope, query: filter.query, emptyText: nil, refreshes: false, showsRunning: false)
                if !sections.neverRan.isEmpty {
                    Section("Hasn't Run Yet") {
                        ForEach(sections.neverRan) { row in actions.rowView(row, now: now) }
                    }
                }
            }
            .listStyle(.inset)
            .overlay { emptyState(sections) }
        }
        .searchable(text: $filter.query, prompt: "Search")
        .searchFocused($searchFocused)
        // A click on a row or on a scope button lets go of the search field in
        // that same click; the field no longer holds the keyboard until Escape.
        .onChange(of: selection) { searchFocused = false }
        .onChange(of: filter.scope) { searchFocused = false }
        .scopeTabsToolbar(screen: "activity", items: scopeTabs, selection: $filter.scope)
        .onKeyPress(.return) {
            guard let row = selection.flatMap(rowFor) else { return .ignored }
            RunRowActions(store: store, navigator: navigator, model: model).open(row)
            return .handled
        }
        .task {
            applyPendingLink()
            await model.refresh(store: store)
        }
        // a link opened while Activity is already showing
        .onChange(of: navigator.pendingIntent) { applyPendingLink() }
        // a review stops waiting at a known moment: look again then
        .task(id: model.nextReviewExpiry) {
            guard let expiry = model.nextReviewExpiry else { return }
            try? await Task.sleep(for: .seconds(max(1, expiry.timeIntervalSinceNow + 1)))
            await model.refresh(store: store)
        }
        .onChange(of: storeStamp) { Task { await model.refresh(store: store) } }
    }

    /// A deep link's scope, search or folded days, applied once.
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: OverviewGroup.activity),
              let link = ActivityLink(payload: payload) else { return }
        link.apply(to: filter)
    }

    private func rowFor(_ id: ActivityRow.ID) -> ActivityRow? { model.rows.first { $0.id == id } }

    // MARK: - chrome

    private var subtitle: String {
        let running = model.rows.filter(\.isRunning).count
        let review = model.rows.filter(\.needsReview).count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if review > 0 { parts.append("\(review) to review") }
        return parts.isEmpty ? "Everything that has run" : parts.joined(separator: " · ")
    }

    /// The screen's categories with how many rows each holds ("All" has no count).
    private var scopeTabs: [ScopeTabItem<ActivityScope>] {
        ActivityScope.allCases.map { scope in
            ScopeTabItem(value: scope, title: scope.title, symbol: scope.symbol,
                         count: scope == .all ? nil : model.rows.filter(scope.includes).count)
        }
    }

    @ViewBuilder private func emptyState(_ sections: ActivitySections) -> some View {
        if model.hasLoaded, sections.running.isEmpty, sections.days.isEmpty, sections.neverRan.isEmpty {
            switch filter.scope {
            case .all where filter.query.isEmpty:
                ContentUnavailableView("Nothing Has Run Yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Cleanups, checks and reports appear here as they run."))
            case .running:
                ContentUnavailableView("Nothing Is Running", systemImage: "play.circle",
                                       description: Text("A cleanup or check that is running shows here, with a Stop button."))
            case .needsReview:
                ContentUnavailableView("Nothing Is Waiting for Review", systemImage: "eye",
                                       description: Text("A preview you ran in the last \(Int(JobStore.reviewWindow / 60)) minutes that found something shows here until you apply or discard it. Older ones stay in the list as what they found."))
            case .failed:
                ContentUnavailableView("Nothing Has Failed", systemImage: "checkmark.circle",
                                       description: Text("Runs that could not finish are listed here, with the reason."))
            default:
                ContentUnavailableView.search(text: filter.query)
            }
        }
    }
}
