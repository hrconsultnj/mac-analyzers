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
///   ActivityScopeToolbar.swift    the All / Running / Needs review / Failed control
///   ActivityRow+Presentation.swift  glyph, time, and where a row leads
///   ActivityInspector.swift       the run screen: outcome, Stop, live output, raw output
///   JobScreen.swift, RunScreen.swift  the pushed screens for `Route.job` and `Route.run`
///   JobStatusToolbarItem.swift    the shell's status item
///   JobFinishNotifier.swift       the notification when a job ends behind a closed window
///   AnalyzersKit/Activity/        the join, the day grouping and the outcome lists, so the probe can print them
struct ActivityView: View {

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var model = ActivityModel()
    @State private var selection: ActivityRow.ID?
    @Bindable private var filter = ActivityFilter.shared

    /// Changes only when a job moves between queued, running and finished.
    private var storeStamp: [JobStamp] { store.jobs.map { JobStamp($0) } }

    var body: some View {
        let sections = model.sections(scope: filter.scope, query: filter.query)
        let now = Date()
        List(selection: $selection) {
            if !sections.running.isEmpty {
                Section("Running Now") {
                    ForEach(sections.running) { row in rowView(row, now: now) }
                }
            }
            ForEach(sections.days) { day in
                ActivityDaySection(day: day, filter: filter, now: now) { row in
                    rowView(row, now: now)
                }
            }
            if !sections.neverRan.isEmpty {
                Section("Hasn't Run Yet") {
                    ForEach(sections.neverRan) { row in rowView(row, now: now) }
                }
            }
        }
        .listStyle(.inset)
        .overlay { emptyState(sections) }
        .navigationTitle("Activity")
        .navigationSubtitle(subtitle)
        .searchable(text: $filter.query, prompt: "Search runs and results")
        .toolbar { ActivityScopeToolbar(scope: $filter.scope) }
        .onKeyPress(.return) {
            guard let row = selection.flatMap(rowFor) else { return .ignored }
            open(row)
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

    // MARK: - rows

    private func rowView(_ row: ActivityRow, now: Date) -> some View {
        ActivityRowView(row: row, now: now, liveLine: liveLine(row), onOpen: { open(row) },
                        onReview: row.needsReview ? { review(row) } : nil,
                        onStop: row.isRunning ? { stop(row) } : nil)
            .tag(row.id)
            .contextMenu { menu(for: row) }
    }

    private func rowFor(_ id: ActivityRow.ID) -> ActivityRow? { model.rows.first { $0.id == id } }

    private func job(for row: ActivityRow) -> Job? {
        row.jobID.flatMap { id in store.jobs.first { $0.id == id } }
    }

    /// A running job's current step, read from the job itself so it moves while
    /// the list's data does not.
    private func liveLine(_ row: ActivityRow) -> String? {
        guard row.status == .running, let job = job(for: row) else { return nil }
        return job.step ?? row.line
    }

    /// A waiting preview's task screen, where it is reviewed and applied.
    private func review(_ row: ActivityRow) {
        if let target = row.reviewTarget { navigator.open(target: target) }
    }

    private func stop(_ row: ActivityRow) { job(for: row)?.cancel() }

    /// A row leads to its own run screen; a task that has not run yet leads to
    /// the task's screen.
    private func open(_ row: ActivityRow) {
        if let route = row.route {
            navigator.push(route)
        } else if let target = row.ownerTarget {
            navigator.open(target: target)
        }
    }

    @ViewBuilder private func menu(for row: ActivityRow) -> some View {
        Button("Open") { open(row) }
        if row.reviewTarget != nil {
            if row.needsReview {
                Button("Review") { review(row) }
            } else if row.intent == .preview, row.findings > 0 {
                Button("Preview Again") { review(row) }
            }
        }
        if let target = row.ownerTarget, row.route != nil {
            Button("Open \(row.title)") { navigator.open(target: target) }
        }
        if row.route != nil {
            Button("Copy Details") { ActivityDetails.copy(row, lines: lines(for: row)) }
            Button("Show Raw Output") {
                RawOutputRequest.ask(for: row.id)
                open(row)
            }
        }
        if row.isRunning {
            Divider()
            Button("Stop", role: .destructive) { stop(row) }
        }
    }

    private func lines(for row: ActivityRow) -> [String] {
        job(for: row)?.lines ?? model.lines(for: row)
    }

    // MARK: - chrome

    private var subtitle: String {
        let running = model.rows.filter(\.isRunning).count
        let review = model.rows.filter(\.needsReview).count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if review > 0 { parts.append("\(review) to review") }
        return parts.isEmpty ? "Everything that has run" : parts.joined(separator: " · ")
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
