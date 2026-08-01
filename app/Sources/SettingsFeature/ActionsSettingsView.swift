import SwiftUI
import AnalyzersKit
import UIComponents

/// REVIEW › Actions — the dry-run → review → apply flow, in-app. Pick a
/// cleaner, preview what it WOULD do (the engine's dry run, parsed by the
/// same parsers the log panes use), review every item, then apply behind an
/// explicit confirmation. The app never applies anything unreviewed.
struct ActionsSettingsView: View {

    enum Cleaner: Hashable, CaseIterable {
        case memoryClean, reclaim, storageClean, janitor

        /// The two storage-shaped cleaners share the review renderer.
        var isStorageShaped: Bool { self == .storageClean || self == .janitor }

        var title: String {
            switch self {
            case .memoryClean: "Memory Clean"
            case .reclaim: "Memory Reclaim"
            case .storageClean: "Storage Clean"
            case .janitor: "Janitor"
            }
        }

        var blurb: String {
            switch self {
            case .memoryClean:
                "Closes orphaned dev helpers and yesterday's forgotten dev servers. Protected apps and live AI sessions are never touched."
            case .reclaim:
                "Sweeps reclaimable dev processes for a bigger one-time memory win. Same protections as the guard."
            case .storageClean:
                "Removes stale build caches and node_modules of idle repos only — anything touched recently is skipped."
            case .janitor:
                "Moves stale Downloads and old screenshots to the Trash — recoverable, keep-patterns honored, folders reviewed as units."
            }
        }

        var symbol: String {
            switch self {
            case .memoryClean: "memorychip"
            case .reclaim: "arrow.3.trianglepath"
            case .storageClean: "internaldrive.fill"
            case .janitor: "trash"
            }
        }

        var color: Color {
            switch self {
            case .memoryClean: .blue
            case .reclaim: .teal
            case .storageClean: .indigo
            case .janitor: .orange
            }
        }

        var script: URL {
            switch self {
            case .memoryClean: AnalyzersPaths.memoryCleanScript
            case .reclaim: AnalyzersPaths.reclaimScript
            case .storageClean: AnalyzersPaths.storageCleanScript
            case .janitor: AnalyzersPaths.janitorScript
            }
        }

        var logKind: LogKind {
            switch self {
            case .memoryClean: .memoryClean
            case .reclaim: .reclaim
            case .storageClean: .storageClean
            case .janitor: .janitor
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case previewing
        case review
        case applying
        case done(String)
        case failed(String)
    }

    @State private var cleaner: Cleaner = .memoryClean
    @State private var phase: Phase = .idle
    @State private var reapRun: ReapRun?
    @State private var storageRun: StorageCleanRun?
    @State private var confirmingApply = false
    /// Storage only: deep mode adds stale node_modules + TM snapshot report
    /// (the engine's --mode deep), vs daily's build-caches-only pass.
    @State private var storageDeep = false

    private var modeArgs: [String] {
        cleaner == .storageClean && storageDeep ? ["--mode", "deep"] : []
    }

    var body: some View {
        PaneScaffold(symbol: "checklist", color: .cyan, title: "Actions",
                     caption: "Preview first, review everything, apply only what you approve — the scripts' dry-run contract, as a screen.") {
            Section {
                FullWidthSegments(
                    options: Cleaner.allCases.map { ($0, $0.title) },
                    selection: $cleaner
                )
                Text(cleaner.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if cleaner == .storageClean {
                    Toggle(isOn: $storageDeep) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Deep mode")
                            Text("Also stale node_modules of idle repos and the Time Machine snapshot report.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(phase != .idle)
                }
            }
            controlSection
            reviewSections
        }
        .onChange(of: cleaner) { resetToIdle() }
        .confirmationDialog(applyPrompt, isPresented: $confirmingApply, titleVisibility: .visible) {
            Button(applyButtonTitle, role: .destructive) {
                Task { await apply() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs \(cleaner.script.lastPathComponent) with --apply. Everything is logged; protected lists always win.")
        }
    }

    // MARK: - control row

    @ViewBuilder private var controlSection: some View {
        Section {
            switch phase {
            case .idle:
                HStack {
                    lastRunText
                    Spacer()
                    Button("Preview (dry run)") {
                        Task { await preview() }
                    }
                    .buttonStyle(.glassProminent)
                }
            case .previewing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Running the dry run — nothing is being changed…")
                        .foregroundStyle(.secondary)
                }
            case .review:
                HStack {
                    Label(reviewHeadline, systemImage: "eye")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Discard") { resetToIdle() }
                    Button(applyButtonTitle) { confirmingApply = true }
                        .buttonStyle(.glassProminent)
                        .disabled(!hasAnythingToApply)
                }
            case .applying:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying — receipts are being written to the log…")
                        .foregroundStyle(.secondary)
                }
            case .done(let summary):
                HStack {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("New preview") { resetToIdle() }
                }
            case .failed(let message):
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button("Try again") { resetToIdle() }
                }
            }
        }
    }

    private var lastRunText: some View {
        Group {
            if let url = cleaner.logKind.url,
               let date = AnalyzersPaths.modificationDate(of: url) {
                Text("Last run \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never run on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                    ForEach(run.groups) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                DataCard(symbol: "terminal", color: statusColor(item.status),
                                         title: item.friendlyName,
                                         subtitle: item.description,
                                         trailing: item.mb.map { "\($0) MB" },
                                         badge: badge(for: item.status))
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
                    let groups = Dictionary(grouping: run.items.filter { $0.status == .dry || $0.status == .deleted || $0.status == .trashed },
                                            by: \.project)
                        .map { (project: $0.key,
                                items: $0.value.sorted { $0.sizeBytes > $1.sizeBytes },
                                total: $0.value.map(\.sizeBytes).reduce(0, +)) }
                        .sorted { $0.total > $1.total }
                    ForEach(groups, id: \.project) { group in
                        Section("\(group.project) — \(ByteSize.format(group.total))") {
                            ForEach(group.items) { item in
                                DataCard(symbol: "folder.fill", color: .indigo,
                                         title: item.cacheKind,
                                         subtitle: item.path,
                                         trailing: ByteSize.format(item.sizeBytes),
                                         badge: item.status == .deleted ? ("DELETED", .red)
                                             : item.status == .trashed ? ("TRASHED", .orange)
                                             : ("WOULD REMOVE", .blue))
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
            }
        }
    }

    private var isApplyingOrDone: Bool {
        if case .applying = phase { return true }
        if case .done = phase { return true }
        return false
    }

    // MARK: - numbers for headlines and buttons

    private var dryReapItems: [ReapItem] {
        reapRun?.allItems.filter { $0.status == .dry } ?? []
    }

    private var dryStorageBytes: Int64 {
        storageRun?.items.filter { $0.status == .dry }.map(\.sizeBytes).reduce(0, +) ?? 0
    }

    private var hasAnythingToApply: Bool {
        switch cleaner {
        case .memoryClean, .reclaim: !dryReapItems.isEmpty
        case .storageClean, .janitor: dryStorageBytes > 0
        }
    }

    private var reviewHeadline: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            let mb = dryReapItems.compactMap(\.mb).reduce(0, +)
            return dryReapItems.isEmpty
                ? "Nothing to close — all clean."
                : "Would close \(dryReapItems.count) process\(dryReapItems.count == 1 ? "" : "es") (~\(mb) MB)"
        case .storageClean, .janitor:
            return dryStorageBytes == 0
                ? "Nothing stale to remove."
                : "Would free \(ByteSize.format(dryStorageBytes))"
        }
    }

    private var applyButtonTitle: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            "Apply — close \(dryReapItems.count)"
        case .storageClean:
            "Apply — free \(ByteSize.format(dryStorageBytes))"
        case .janitor:
            "Apply — trash \(ByteSize.format(dryStorageBytes))"
        }
    }

    private var applyPrompt: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            "Close \(dryReapItems.count) process\(dryReapItems.count == 1 ? "" : "es")?"
        case .storageClean:
            "Remove the listed caches (\(ByteSize.format(dryStorageBytes)))?"
        case .janitor:
            "Move the listed items (\(ByteSize.format(dryStorageBytes))) to the Trash?"
        }
    }

    // MARK: - engine calls

    private func preview() async {
        phase = .previewing
        let result = await ActionRunner.run(script: cleaner.script, args: ["--dry-run"] + modeArgs)
        guard result.exitCode == 0 else {
            phase = .failed("Dry run exited \(result.exitCode) — see the log for details.")
            return
        }
        parseLatestRun()
        phase = .review
    }

    private func apply() async {
        phase = .applying
        let result = await ActionRunner.run(script: cleaner.script, args: ["--apply"] + modeArgs)
        guard result.exitCode == 0 else {
            phase = .failed("Apply exited \(result.exitCode) — see the log for details.")
            return
        }
        parseLatestRun()
        phase = .done(doneSummary)
    }

    private var doneSummary: String {
        switch cleaner {
        case .memoryClean, .reclaim:
            let closed = reapRun?.allItems.filter { $0.status == .killed || $0.status == .quit } ?? []
            let mb = closed.compactMap(\.mb).reduce(0, +)
            return closed.isEmpty ? "Done — nothing needed closing."
                                  : "Closed \(closed.count) — freed ~\(mb) MB. Receipts in the log."
        case .storageClean:
            let freed = storageRun?.items.filter { $0.status == .deleted }
                .map(\.sizeBytes).reduce(0, +) ?? 0
            return freed == 0 ? "Done — nothing removed."
                              : "Freed \(ByteSize.format(freed)). Receipts in the log."
        case .janitor:
            let trashed = storageRun?.items.filter { $0.status == .trashed }
                .map(\.sizeBytes).reduce(0, +) ?? 0
            return trashed == 0 ? "Done — nothing needed tidying."
                                : "Moved \(ByteSize.format(trashed)) to the Trash — recoverable there."
        }
    }

    private func parseLatestRun() {
        guard let latest = LogParser.runs(for: cleaner.logKind).first else {
            reapRun = nil
            storageRun = nil
            return
        }
        switch cleaner {
        case .memoryClean, .reclaim:
            reapRun = ReapParser.parse(runHeader: latest.header, lines: latest.lines)
        case .storageClean, .janitor:
            storageRun = StorageCleanParser.parse(runHeader: latest.header, lines: latest.lines)
        }
    }

    private func resetToIdle() {
        phase = .idle
        reapRun = nil
        storageRun = nil
    }

    private func statusColor(_ status: ReapItem.Status) -> Color {
        switch status {
        case .dry: .blue
        case .killed, .quit: .red
        case .reported: .purple
        case .exempt: .green
        case .gone, .skip: .secondary
        }
    }

    private func badge(for status: ReapItem.Status) -> (String, Color)? {
        switch status {
        case .dry: ("WOULD CLOSE", .blue)
        case .killed: ("CLOSED", .red)
        case .quit: ("QUIT", .red)
        case .reported: ("REPORTED", .purple)
        case .exempt: ("PROTECTED", .green)
        case .gone: ("GONE", .gray)
        case .skip: nil
        }
    }
}
