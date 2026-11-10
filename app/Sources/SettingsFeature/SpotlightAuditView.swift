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
struct SpotlightAuditView: View {

    private enum Filter: String, CaseIterable {
        case all = "All"
        case unfenced = "Unfenced"
        case fenced = "Fenced"
    }

    /// The two script-run actions this pane can trigger. Deliberately not
    /// phase-gating the rest of the pane (unlike ActionsSettingsView's
    /// preview→review→apply flow) — the exposure list stays visible and
    /// interactive the whole time; this only drives the small status line
    /// under the action row.
    private enum RunPhase: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    @State private var run: SpotlightAuditRun?
    @State private var filter: Filter = .all
    @State private var copiedCommand: String?
    @State private var runPhase: RunPhase = .idle
    @State private var confirmingApply = false
    /// Bumped after a per-row fence/unfence so SwiftUI re-renders — the
    /// change itself is a bare FileManager side effect it has no other way
    /// to observe (no @Published, no re-parsed log).
    @State private var fenceVersion = 0

    var body: some View {
        PaneScaffold(symbol: "magnifyingglass", color: .yellow, title: "Spotlight Audit",
                     caption: "Is Finder search keeping up, and is it wasting time indexing node_modules and build output? Reads the indexer's own state and fences dev directories it never needs to see — reversibly.") {
            Section {
                HStack {
                    Spacer(minLength: 8)
                    Button("Run audit") { Task { await runAudit() } }
                        .disabled(isBusy)
                        .help("Runs spotlight-audit.sh --dry-run and refreshes this pane. Changes nothing.")
                    Button("Apply fences") { confirmingApply = true }
                        .buttonStyle(.glassProminent)
                        .disabled(isBusy)
                        .help("Runs spotlight-audit.sh --apply — fences every unfenced dev directory found under the configured roots.")
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
        .task { await load() }
        .confirmationDialog(applyPrompt, isPresented: $confirmingApply, titleVisibility: .visible) {
            Button("Apply fences", role: .destructive) {
                Task { await applyFences() }
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

    // MARK: - section 1: indexing status

    @ViewBuilder private func statusSection(_ run: SpotlightAuditRun) -> some View {
        Section("Indexing status") {
            DataCard(symbol: statusSymbol(run), color: statusColor(run),
                     title: run.indexingLine ?? "Indexing status unknown",
                     subtitle: run.mdsLine.map { "mds/mdworker: \($0)" })
            if let update = run.recentUpdateLine {
                DataCard(symbol: "arrow.triangle.2.circlepath", color: .purple,
                         title: "Recent macOS update", subtitle: update)
            }
            if !run.statusRaw.isEmpty {
                rawBlock(run.statusRaw)
            }
        }
    }

    private func statusSymbol(_ run: SpotlightAuditRun) -> String {
        indexingDisabled(run) ? "xmark.shield" : "checkmark.shield"
    }

    private func statusColor(_ run: SpotlightAuditRun) -> Color {
        indexingDisabled(run) ? .red : .green
    }

    private func indexingDisabled(_ run: SpotlightAuditRun) -> Bool {
        run.indexingLine?.lowercased().contains("disabled") ?? false
    }

    // MARK: - section 2: verdict

    @ViewBuilder private func verdictSection(_ run: SpotlightAuditRun) -> some View {
        Section("Stuck or progressing?") {
            DataCard(symbol: verdictSymbol(run.verdict), color: verdictColor(run.verdict),
                     title: verdictTitle(run.verdict),
                     subtitle: run.verdictDetail,
                     badge: (run.verdict.rawValue, verdictColor(run.verdict)))
            if let cmd = run.deepCheckCommand {
                commandRow("Deep check — the definitive signal", cmd)
            }
            if let cmd = run.rebuildCommand {
                commandRow("Only if genuinely stuck 24h+", cmd)
            }
            if !run.verdictRaw.isEmpty {
                rawBlock(run.verdictRaw)
            }
        }
    }

    private func commandRow(_ caption: String, _ cmd: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(cmd)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Tokens.Surface.tile, in: RoundedRectangle(cornerRadius: Tokens.Radius.chip))
                Button(copiedCommand == cmd ? "Copied ✓" : "Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    copiedCommand = cmd
                }
                .controlSize(.small)
            }
        }
    }

    private func verdictTitle(_ verdict: SpotlightAuditRun.Verdict) -> String {
        switch verdict {
        case .progressing: "Progressing"
        case .idleOrComplete: "Idle or complete"
        case .notRunning: "Not running"
        case .unknown: "Unknown"
        }
    }

    private func verdictSymbol(_ verdict: SpotlightAuditRun.Verdict) -> String {
        switch verdict {
        case .progressing: "arrow.triangle.2.circlepath"
        case .idleOrComplete: "checkmark.circle"
        case .notRunning: "moon.zzz"
        case .unknown: "questionmark.circle"
        }
    }

    private func verdictColor(_ verdict: SpotlightAuditRun.Verdict) -> Color {
        switch verdict {
        case .progressing: .blue
        case .idleOrComplete: .green
        case .notRunning: .gray
        case .unknown: .secondary
        }
    }

    // MARK: - section 3: dev-directory exposure

    @ViewBuilder private func exposureSection(_ run: SpotlightAuditRun) -> some View {
        Section {
            FilterChipsBar(
                chips: Filter.allCases.map { f in
                    .init(f, f.rawValue, count: count(f, run), color: chipColor(f))
                },
                selection: $filter
            )
            HStack(spacing: 6) {
                Text("Fenced \(run.fencedCount) · Unfenced \(run.unfencedCount)"
                     + (run.unfencedBulkText.map { " · \($0) out of the index" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let hint = run.applyHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Dev-directory exposure" + (run.exposureRoots.map { " (roots: \($0))" } ?? ""))
        }

        let items = filteredItems(run)
        if items.isEmpty {
            Section {
                Label("Nothing exposed — every dev directory found here is already fenced.",
                      systemImage: "checkmark.shield")
                    .foregroundStyle(.green)
            }
        } else {
            ForEach(groupedByProject(items), id: \.project) { group in
                Section("\(group.project) — \(ByteSize.format(group.total))") {
                    ForEach(group.items) { item in
                        exposureRow(item)
                    }
                }
            }
        }
    }

    /// Fenced state per row is read straight off disk, not off the parsed
    /// log line — the log's [DRY]/[FENCED] tag is only as fresh as the last
    /// script run, and a Fence/Unfence tap here doesn't re-run the script.
    /// The log still supplies the identity (path) and size; disk supplies
    /// truth about whether the marker exists right now.
    private func exposureRow(_ item: SpotlightExposureItem) -> some View {
        let exists = FileManager.default.fileExists(atPath: item.path)
        let fenced = liveStatus(item) == .fenced
        let badge = (fenced ? "FENCED" : "UNFENCED", fenced ? Color.green : Color.blue)
        return HStack(spacing: 6) {
            if exists {
                DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                         title: item.cacheKind, subtitle: item.path,
                         trailing: ByteSize.format(item.sizeBytes), badge: badge)
            } else {
                DataCard(symbol: "shippingbox.fill", color: badge.1,
                         title: item.cacheKind, subtitle: item.path,
                         trailing: ByteSize.format(item.sizeBytes), badge: badge)
            }
            if exists {
                Button(fenced ? "Unfence" : "Fence") { toggleFence(item) }
                    .controlSize(.small)
                    .help(fenced
                          ? "Delete the .metadata_never_index marker — Spotlight re-indexes this directory."
                          : "Create a .metadata_never_index marker — Spotlight stops indexing this directory.")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    .accessibilityLabel("Show in Finder")
            }
        }
        // Directory is gone from disk since the audit ran — nothing to
        // fence/unfence or reveal; the row stays visible (it's still true
        // the audit found it) but reads as inert, same weight the review
        // list in Actions gives a deselected row.
        .opacity(exists ? 1 : 0.45)
    }

    private func markerPath(_ item: SpotlightExposureItem) -> String {
        (item.path as NSString).appendingPathComponent(".metadata_never_index")
    }

    private func liveStatus(_ item: SpotlightExposureItem) -> SpotlightExposureItem.Status {
        // Read (not just write) fenceVersion so SwiftUI's dependency
        // tracking — driven by what a render pass actually reads, even
        // through a helper call — ties this row to the toggle below.
        _ = fenceVersion
        return FileManager.default.fileExists(atPath: markerPath(item)) ? .fenced : .dry
    }

    /// Direct FileManager marker create/delete — the app doing exactly what
    /// the script documents as the manual reversal (`rm .metadata_never_index`),
    /// no script invocation needed for a single directory. No success/failure
    /// state to track: the row re-reads the marker from disk right after, so
    /// a silent failure (e.g. permissions) just shows as "nothing changed"
    /// rather than needing its own error path.
    private func toggleFence(_ item: SpotlightExposureItem) {
        let marker = markerPath(item)
        let fm = FileManager.default
        if fm.fileExists(atPath: marker) {
            try? fm.removeItem(atPath: marker)
        } else {
            fm.createFile(atPath: marker, contents: nil)
        }
        fenceVersion += 1
    }

    private struct ExposureGroup { let project: String; let items: [SpotlightExposureItem]; let total: Int64 }

    private func groupedByProject(_ items: [SpotlightExposureItem]) -> [ExposureGroup] {
        Dictionary(grouping: items, by: \.project)
            .map { key, value in
                ExposureGroup(project: key,
                              items: value.sorted { $0.sizeBytes > $1.sizeBytes },
                              total: value.reduce(Int64(0)) { $0 + $1.sizeBytes })
            }
            .sorted { $0.total > $1.total }
    }

    /// Filtered on live status (see `exposureRow`) so a row a user just
    /// fenced/unfenced moves to the right chip immediately, without waiting
    /// on a fresh script run.
    private func filteredItems(_ run: SpotlightAuditRun) -> [SpotlightExposureItem] {
        switch filter {
        case .all: run.exposureItems
        case .unfenced: run.exposureItems.filter { liveStatus($0) == .dry }
        case .fenced: run.exposureItems.filter { liveStatus($0) == .fenced }
        }
    }

    private func count(_ f: Filter, _ run: SpotlightAuditRun) -> Int {
        switch f {
        case .all: run.exposureItems.count
        case .unfenced: run.exposureItems.filter { liveStatus($0) == .dry }.count
        case .fenced: run.exposureItems.filter { liveStatus($0) == .fenced }.count
        }
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .all: .yellow
        case .unfenced: .blue
        case .fenced: .green
        }
    }

    /// Prose the script wrote that didn't map to a specific field — shown
    /// verbatim rather than dropped, same "degrade honestly" idea as
    /// StorageCleanView's third-party raw-output block.
    private func rawBlock(_ lines: [String]) -> some View {
        DisclosureGroup("Details") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - actions

    /// `--dry-run`: status + verdict + exposure, nothing touched.
    private func runAudit() async {
        runPhase = .running("Running audit — nothing is being changed…")
        let result = await ActionRunner.run(script: AnalyzersPaths.spotlightAuditScript, args: ["--dry-run"])
        guard result.exitCode == 0 else {
            runPhase = .failed(ActionsSettingsView.explain(exitCode: result.exitCode, verb: "run the audit"))
            return
        }
        runPhase = .done("Audit complete.")
        await load(force: true)
    }

    /// `--apply`: fences every unfenced dev directory under the configured
    /// roots. Gated by the confirmation dialog — this is the one action
    /// here that isn't instantly, individually reversible the way a single
    /// row's Fence/Unfence is (it acts on everything at once).
    private func applyFences() async {
        runPhase = .running("Fencing unfenced dev directories…")
        let result = await ActionRunner.run(script: AnalyzersPaths.spotlightAuditScript, args: ["--apply"])
        guard result.exitCode == 0 else {
            runPhase = .failed(ActionsSettingsView.explain(exitCode: result.exitCode, verb: "apply fences"))
            return
        }
        runPhase = .done("Fences applied.")
        await load(force: true)
    }

    // MARK: - load

    /// `force` bypasses the LoadCoordinator's 3s TTL for this call only —
    /// needed right after a script run, where the log just changed and the
    /// cached parse (same call-site key as the normal `.task`/Refresh load)
    /// would otherwise still be "fresh enough" to serve stale.
    private func load(force: Bool = false) async {
        await awaitLoad({
            LogParser.runs(for: .spotlightAudit).first.map {
                SpotlightAuditParser.parse(runHeader: $0.header, lines: $0.lines)
            }
        }, ttl: force ? 0 : 3) { run = $0 }
    }
}
