import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// REVIEW › Actions — the dry-run → review → apply flow, in-app. Pick a
/// cleaner, preview what it WOULD do (the engine's dry run, parsed by the
/// same parsers the log panes use), review every item, then apply behind an
/// explicit confirmation. The app never applies anything unreviewed.
///
/// This file is the screen's state and its composition. One job per file next to it:
///   Cleaner.swift                          the five cleaners: names, scripts, logs
///   ActionsSettingsView+Control.swift      the phase row (preview / review / apply / done)
///   ActionsSettingsView+ReapReview.swift   review of the process cleaners
///   ActionsSettingsView+PathReview.swift   review of the storage cleaners
///   ActionsSettingsView+TempReview.swift   review of Temp & Agents
///   ActionsSettingsView+Approval.swift     per-item selection and the approved set
///   ActionsSettingsView+History.swift      previous runs, parsed from the logs
///   ActionsSettingsView+Engine.swift       preview and apply as jobs, read the run back from the job
///   AnalyzersKit/Jobs/ExitExplanation.swift  exit code to sentence
struct ActionsSettingsView: View {

    enum Phase: Equatable {
        case idle
        case previewing
        case review
        case applying
        case done(String)
        case failed(String)
    }

    @Environment(JobStore.self) var jobs
    @Binding var preselect: String?
    @State var cleaner: Cleaner = .memoryClean
    @State var phase: Phase = .idle
    /// This cleaner's jobs: the store's own, found again by kind when the
    /// window is reopened. The review is of `previewJob`; an apply can only be
    /// built from it (`JobStore.apply(from:approved:)`), and `applyJob` is that apply.
    @State var previewJob: Job?
    @State var applyJob: Job?
    /// Rows the user unticked in the review. Stored as the *exclusion* set so
    /// a fresh preview starts with everything approved, which is what the
    /// preview→apply flow has always implied.
    @State var deselected: Set<String> = []
    @State var reapRun: ReapRun?
    @State var storageRun: StorageCleanRun?
    @State var tempRun: TempCleanRun?
    @State var confirmingApply = false
    /// Temp only: the second, plain-words confirmation a permanent delete
    /// gets on top of the usual one.
    @State private var confirmingPermanent = false
    @State var sortByName = false
    @State var history: [HistoryRun] = []
    @State var lastOutput = ""
    /// Storage only: deep mode adds stale node_modules + TM snapshot report
    /// (the engine's --mode deep), vs daily's build-caches-only pass.
    @State var storageDeep = false
    /// Temp only: delete instead of moving to the Trash (the engine's --permanent).
    @State var tempPermanent = false

    var modeArgs: [String] {
        switch cleaner {
        case .storageClean: storageDeep ? ["--mode", "deep", "--prune-snapshots"] : []
        case .tempClean: tempPermanent ? ["--permanent"] : []
        case .memoryClean, .reclaim, .janitor: []
        }
    }

    /// Recoverable for THIS run — temp clean stops being so when permanent
    /// is chosen, and every label and confirmation must say which.
    var recoverableNow: Bool {
        cleaner.isRecoverable && !(cleaner == .tempClean && tempPermanent)
    }

    var body: some View {
        PaneScaffold(symbol: "checklist", color: .cyan, title: "Actions",
                     caption: "Preview what a cleaner would do, untick anything you want kept, then apply. Only the rows you leave ticked can be touched — and the engine re-checks everything at apply time, which can only narrow that set further, never widen it.") {
            Section {
                FullWidthSegments(
                    options: Cleaner.allCases.map { ($0, $0.title) },
                    selection: $cleaner
                )
                HStack(spacing: 6) {
                    BadgeCapsule(text: recoverableNow ? "GOES TO TRASH" : "PERMANENT",
                                 color: recoverableNow ? .orange : .red)
                    Text(cleaner.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if cleaner == .storageClean {
                    Toggle(isOn: $storageDeep) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Deep mode")
                            Text("Also downloaded code for projects you haven't touched lately (node_modules), and the Time Machine snapshot report.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(phase != .idle)
                }
                if cleaner == .tempClean {
                    Toggle(isOn: $tempPermanent) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Delete permanently")
                            Text("Frees the space immediately — no Trash, no Undo. You'll be asked twice.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(phase != .idle)
                }
            }
            controlSection
            reviewSections
            historySection
        }
        .onChange(of: cleaner) {
            adoptCurrentJobs()
            Task { await loadHistory() }
        }
        .onChange(of: preselect) { consumePreselect() }
        .onChange(of: jobStamps) { syncFromJobs() }
        .task {
            consumePreselect()
            adoptCurrentJobs()
            await loadHistory()
        }
        .confirmationDialog(applyPrompt, isPresented: $confirmingApply, titleVisibility: .visible) {
            Button(applyButtonTitle, role: .destructive) {
                if cleaner == .tempClean && tempPermanent {
                    confirmingPermanent = true
                } else {
                    apply()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The first sentence must say whether this can be taken back.
            // "Everything is logged" was doing that job badly while storage
            // clean does rm -rf and an Undo row sits three rows away.
            Text(recoverableNow
                 ? "These move to the Trash, so you can put them back — from the Undo screen or from Finder. Everything is logged; protected lists always win."
                 : cleaner == .tempClean
                    ? "This is PERMANENT — these items are deleted, not moved to the Trash, and Undo cannot bring them back. Temp files and agent scratch are disposable by design, but check the list for anything of yours. Everything is logged."
                    : "This is PERMANENT — these files are deleted, not moved to the Trash, and Undo cannot bring them back. They are rebuildable: your tools recreate them when needed. Everything is logged; protected lists always win.")
        }
        .alert("Delete permanently — this can't be undone", isPresented: $confirmingPermanent) {
            Button("Delete \(ByteSize.format(tempSelectedBytes))", role: .destructive) {
                apply()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(approvedCount) item\(approvedCount == 1 ? "" : "s") will be removed from this Mac for good. To keep a way back, cancel and turn off Delete permanently — they will go to the Trash instead.")
        }
    }

    /// Applies a deep-link request once, then clears it — so re-delivery to
    /// an already-visible pane still works and nothing leaks to next time.
    private func consumePreselect() {
        guard let raw = preselect else { return }
        preselect = nil
        if let requested = Cleaner(rawValue: raw) { cleaner = requested }
    }

    // MARK: - review rendering (same anatomy as the log panes)

    @ViewBuilder private var reviewSections: some View {
        if phase == .review || isApplyingOrDone {
            switch cleaner {
            case .memoryClean, .reclaim:
                if let run = reapRun {
                    if let exempt = run.exemptNote, !exempt.isEmpty {
                        Section {
                            DataCard(symbol: "shield.fill", color: .green,
                                     title: "Protected sessions are exempt",
                                     subtitle: exempt, badge: ("PROTECTED", .green))
                        }
                    }
                    if phase == .review, !dryReapItems.isEmpty {
                        Section { selectionBar }
                    }
                    ForEach(run.groups) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                selectable(item.status == .dry ? item.pid.map(String.init) : nil,
                                           name: item.friendlyName) {
                                    DataCard(symbol: "terminal", color: statusColor(item.status),
                                             title: item.friendlyName,
                                             subtitle: item.description,
                                             trailing: item.mb.map { "\($0) MB" },
                                             badge: badge(for: item.status))
                                }
                            }
                            ForEach(group.aggregates, id: \.label) { agg in
                                DataCard(symbol: "square.stack.3d.up", color: .secondary,
                                         title: "\(agg.count)× \(agg.label)",
                                         trailing: "\(agg.totalMB) MB total")
                            }
                        }
                    }
                }
            case .storageClean, .janitor:
                if let run = storageRun {
                    if phase == .review, dryStorageBytes > 0 {
                        Section { selectionBar }
                    }
                    ForEach(reviewGroups(from: run), id: \.project) { group in
                        Section("\(group.project) — \(ByteSize.format(group.total))") {
                            ForEach(group.items) { item in
                                selectable(item.status == .dry ? item.path : nil,
                                           name: item.cacheKind) {
                                    pathRow(item)
                                }
                            }
                        }
                    }
                    if let tm = run.tmNote {
                        Section {
                            DataCard(symbol: "clock.arrow.circlepath", color: .purple,
                                     title: "Time Machine snapshots", subtitle: tm)
                        }
                    }
                }
            case .tempClean:
                tempReviewSections
            }
        }
    }
}
