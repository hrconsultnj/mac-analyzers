import AnalyzersKit
import SwiftUI
import UIComponents

/// Memory Cleanup: find what is using memory for nothing, look at it, then close what
/// you choose. The screen is a table of contents; each job has its own file next to it.
///
///   MemoryCleanupModel.swift     which cleanup, its options, the preview job, the review read back
///   CleanupReviewRows.swift      the findings as rows for the shared review table, and the tabs
///   CleanupPhases.swift          what the screen shows before, while and after: idle, running, done, failed
///   CleanupResults.swift         a finished run's results (the run screen's slot for this task)
///   CleanupLink.swift            the scope a deep link asks for
///
/// A preview, and the apply built from it, are jobs in the one job store: leaving and coming
/// back finds the same progress or the same review, and Apply goes only through the store.
/// The review is the shared review table: categories are the tabs, an app or a project is a
/// row that opens, programs a live coding session owns are listed but cannot be ticked.
struct MemoryCleanupView: View {
    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(ConfigStore.self) private var config
    @State private var model = MemoryCleanupModel()
    @State private var tab = CleanupTab.other

    var body: some View {
        DataScreen(title: Names.Screen.memoryCleanup, subtitle: subtitle) { content }
            .toolbar { toolbar }
            .onAppear {
                applyPendingLink()
                model.adopt(store: store)
            }
            .onChange(of: model.scope) { model.adopt(store: store) }
            .onChange(of: model.stamps) { model.sync() }
            .task(id: model.phase == .review) {
                // while a review is open, look every few seconds for a program that has changed
                while model.phase == .review, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    model.recheck()
                }
            }
            .onChange(of: navigator.pendingIntent) {
                applyPendingLink()
                model.adopt(store: store)
            }
    }

    // MARK: - what is shown

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            CleanupIdle(scope: model.scope, preview: preview)
        case .previewing, .applying:
            if let job = model.shownJob {
                CleanupRunning(job: job, applying: model.phase == .applying)
            }
        case .review:
            reviewTable
        case .done(let summary):
            if let review = model.review {
                CleanupResultsView(review: review, screen: "cleanup", note: summary)
            }
        case .failed(let message):
            CleanupFailed(message: message, preview: preview)
        }
    }

    @ViewBuilder private var reviewTable: some View {
        if let session = model.session, let job = model.previewJob, let review = model.review {
            let tabs = CleanupTabs(review, includingAppQuits: false)
            let current = tabs.items.contains { $0.value == tab } ? tab : (tabs.items.first?.value ?? tab)
            let apps = review.appQuits.map(\.name)
            ReviewTable(session: session, preview: job, applyTitle: Names.Cleanup.closePrograms,
                        confirmation: ReviewConfirmation(
                            verb: "Close", destination: apps.isEmpty ? "now" : "now, and quit \(apps.joined(separator: ", "))",
                            message: apps.isEmpty
                                ? "Each program is asked to stop. Programs that belong to a live coding session are never touched."
                                : "Each program is asked to stop, and \(apps.joined(separator: ", ")) \(apps.count == 1 ? "is" : "are") asked to quit; they still ask before discarding unsaved work. Programs that belong to a live coding session are never touched.",
                            permanent: nil),
                        note: review.protectedNote,
                        onPreviewAgain: preview,
                        onApplied: { model.applied($0) },
                        only: tabs.hasTabs ? tabs.rowIDs[current] : nil,
                        approval: { model.approval(for: $0) })
                .modifier(CleanupTabsModifier(tabs: tabs, screen: "cleanup", selection: $tab))
                .safeAreaInset(edge: .top, spacing: 0) { appQuitNote(review.appQuits) }
        }
    }

    /// The apps that will be asked to quit as well. They are not rows (they are not ticked), so they are said here.
    @ViewBuilder private func appQuitNote(_ apps: [CleanupCandidate]) -> some View {
        if !apps.isEmpty {
            let names = apps.map(\.name).joined(separator: ", ")
            HStack {
                Label("\(apps.count == 1 ? "This app is" : "These apps are") on your list and will be asked to quit as well: \(names). Turn off Also Quit in Options to leave \(apps.count == 1 ? "it" : "them") open.",
                      systemImage: "app.badge")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .idle: return model.scope.title
        case .previewing: return "Looking for programs…"
        case .applying: return "Closing programs…"
        case .review:
            guard let review = model.review, let session = model.session else { return "" }
            let selected = session.selectedRows
            if selected.isEmpty { return "Nothing selected" }
            // Select All ticks every tab: never let a person approve rows on a tab they have not looked at unknowingly
            let tabs = CleanupTabs(review, includingAppQuits: false)
            let current = tabs.items.contains { $0.value == tab } ? tab : (tabs.items.first?.value ?? tab)
            let inView = tabs.rowIDs[current] ?? []
            let covers = tabs.hasTabs ? tabs.tabsCovered(by: selected.map(\.id)) : 1
            let beyond = tabs.hasTabs && selected.contains { !inView.contains($0.id) }
            let size = ByteSize.format(session.selectedBytes)
            let apps = review.appQuits.count
            let quits = apps == 0 ? "" : " · \(apps) \(apps == 1 ? "app" : "apps") will quit"
            return (beyond ? "\(selected.count) selected across \(covers) tabs · \(size)" : "\(selected.count) selected · \(size)") + quits
        case .done(let summary): return summary
        case .failed: return "Didn't finish"
        }
    }

    // MARK: - actions

    private func preview() {
        model.preview(store: store, reclaimApps: config.memory.reclaimApps)
    }

    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: MemoryGroup.memoryCleanup),
              let link = CleanupLink(payload: payload) else { return }
        if let scope = link.scope { model.scope = scope }
    }

    // MARK: - toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        let busy = model.phase == .previewing || model.phase == .applying
        ToolbarItem(placement: .primaryAction) {
            if busy {
                Button(Names.Stop.stop, systemImage: "stop.circle") { model.stop() }
                    .help("Stop \(model.phase == .applying ? "closing programs" : "looking")")
            } else {
                Button(model.phase == .review ? Names.Review.previewAgain : Names.Cleanup.preview,
                       systemImage: "eye") { preview() }
                    .help("Look at what this cleanup would close. Nothing is closed until you choose Close Programs.")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker(Names.Cleanup.cleanup, selection: $model.scope) {
                    ForEach(MemoryCleanupModel.Scope.allCases) { scope in
                        Label(scope.title, systemImage: scope.symbol).tag(scope)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.scope.title, systemImage: model.scope.symbol)
            }
            .disabled(busy)
            .help("Choose which cleanup to preview")
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                if model.scope == .leftovers {
                    Toggle(Names.Cleanup.busyOrphans, isOn: $model.includeBusyOrphans)
                } else {
                    Toggle("\(Names.Cleanup.alsoQuit) \(appsText)", isOn: $model.alsoQuit)
                        .disabled(config.memory.reclaimApps.isEmpty)
                }
            } label: {
                Label(Names.Cleanup.options, systemImage: "slider.horizontal.3")
            }
            .disabled(busy)
            .help(model.scope == .leftovers
                  ? "Also include leftovers that are still busy, not only idle ones"
                  : "Also ask the apps on your list (Settings, Memory) to quit")
        }
        ToolbarItem(placement: .secondaryAction) {
            if let job = model.shownJob, !busy {
                Button(Names.Raw.screen, systemImage: "text.alignleft") {
                    navigator.push(.overview(.raw(.job(job.id))))
                }
                .help("Show the text this run printed")
            }
        }
    }

    private var appsText: String {
        let apps = config.memory.reclaimApps
        return apps.isEmpty ? "(none on your list)" : apps.prefix(3).joined(separator: ", ") + (apps.count > 3 ? ", …" : "")
    }
}

/// The category tabs for a review, in the toolbar; none when there is only one kind of thing.
struct CleanupTabsModifier: ViewModifier {
    let tabs: CleanupTabs
    let screen: String
    @Binding var selection: CleanupTab

    @ViewBuilder func body(content: Content) -> some View {
        if tabs.hasTabs {
            content.scopeTabsToolbar(
                screen: screen, items: tabs.items,
                // the first category shows as selected until a person chooses another
                selection: Binding(get: { tabs.items.contains { $0.value == selection } ? selection : tabs.items[0].value },
                                   set: { selection = $0 }))
        } else {
            content
        }
    }
}
