import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Spotlight Audit pane: indexing status, the stuck-vs-progressing verdict,
/// and dev-directory exposure — the wall of unfenced node_modules becomes a
/// sized, groupable list, with the two manual commands the script
/// deliberately leaves to a human (the deep check, and the one correct
/// rebuild command) as copyable rows, the same treatment LoginItemsView
/// gives its sudo remediation commands.
///
/// This file is the screen's state and its composition. One job per file next to it:
///   SpotlightAuditView+Status.swift        Section 1: whether Spotlight indexing is on and how it is going.
///   SpotlightAuditView+Verdict.swift       Section 2: the stuck-versus-progressing verdict and the copyable manual commands.
///   SpotlightAuditView+Exposure.swift      Section 3: unfenced dev directories as a sized, filterable, fence-able list.
///   SpotlightAuditView+Actions.swift       Run the audit and apply fences as jobs, and load the latest audit.
struct SpotlightAuditView: View {

    enum Filter: String, CaseIterable {
        case all = "All"
        case unfenced = "Unfenced"
        case fenced = "Fenced"
    }

    /// The two script-run actions this pane can trigger. Deliberately not
    /// phase-gating the rest of the pane (unlike ActionsSettingsView's
    /// preview→review→apply flow) — the exposure list stays visible and
    /// interactive the whole time; this only drives the small status line
    /// under the action row.
    enum RunPhase: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    @Environment(JobStore.self) var jobs
    @State var run: SpotlightAuditRun?
    @State var filter: Filter = .all
    @State var copiedCommand: String?
    /// The audit or the fencing this screen shows: the store's own job, found
    /// again by kind when the window is reopened mid-run. `runPhase` is read off it.
    @State var job: Job?
    @State private var confirmingApply = false
    /// Bumped after a per-row fence/unfence so SwiftUI re-renders — the
    /// change itself is a bare FileManager side effect it has no other way
    /// to observe (no @Published, no re-parsed log).
    @State var fenceVersion = 0

    var body: some View {
        PaneScaffold(symbol: "magnifyingglass", color: .yellow, title: "Spotlight Audit",
                     caption: "Is Finder search keeping up, and is it wasting time indexing node_modules and build output? Reads the indexer's own state and fences dev directories it never needs to see — reversibly.") {
            Section {
                HStack {
                    Spacer(minLength: 8)
                    Button("Run audit") { runAudit() }
                        .disabled(isBusy)
                        .help("Runs spotlight-audit.sh --dry-run and refreshes this pane. Changes nothing.")
                    // redrawn once, when the audit stops being recent enough to apply from
                    TimelineView(.explicit(jobs.latest(.spotlight, intents: [.preview])?.reviewExpiry.map { [$0] } ?? [])) { _ in
                        Button("Apply fences") { confirmingApply = true }
                            .buttonStyle(.glassProminent)
                            .disabled(isBusy || reviewedAudit == nil)
                            .help(reviewedAudit == nil
                                  ? (reviewExpired
                                     ? "The last audit is more than \(Int(JobStore.reviewWindow / 60)) minutes old. Run the audit again — fences are applied from an audit you have just seen."
                                     : "Run the audit first — fences are applied from an audit you have just seen.")
                                  : "Runs spotlight-audit.sh --apply — fences every unfenced dev directory found under the configured roots.")
                    }
                    Button("Open in TextEdit") { GuardControl.openLog(AnalyzersPaths.spotlightAuditLog) }
                    Button {
                        Task { await load() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                        .accessibilityLabel("Refresh")
                }
                switch runPhase {
                case .idle:
                    EmptyView()
                case .running(let label):
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(label).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Stop") { job?.cancel() }
                            .controlSize(.small)
                    }
                case .done(let summary):
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let run {
                    HStack(spacing: 6) {
                        BadgeCapsule(text: run.dryRun ? "DRY RUN" : "APPLIED",
                                     color: run.dryRun ? .blue : .green)
                        Text(run.summary ?? run.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let run {
                statusSection(run)
                verdictSection(run)
                exposureSection(run)
            } else {
                Section {
                    Text("No check logged yet — this runs with the storage suite, or run spotlight-audit.sh yourself for a fresh pass.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            adoptCurrentJob()
            await load()
        }
        .onChange(of: job?.stamp) { _, stamp in
            guard let stamp, stamp.stage == .succeeded else { return }
            Task { await load(force: true) }
        }
        .confirmationDialog(applyPrompt, isPresented: $confirmingApply, titleVisibility: .visible) {
            Button("Apply fences", role: .destructive) {
                applyFences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a .metadata_never_index marker in every unfenced dev directory the audit finds — reversible any time, per directory, from the Unfence button here (or by deleting the marker file yourself). Already-fenced directories are left alone.")
        }
    }

    private var isBusy: Bool {
        if case .running = runPhase { return true }
        return false
    }

    private var applyPrompt: String {
        let n = run?.exposureItems.filter { liveStatus($0) == .dry }.count
        return n.map { "Fence \($0) unfenced director\($0 == 1 ? "y" : "ies")?" } ?? "Fence unfenced dev directories?"
    }
}
