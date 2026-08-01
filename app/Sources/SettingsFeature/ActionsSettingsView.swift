import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// REVIEW › Actions — the dry-run → review → apply flow, in-app. Pick a
/// cleaner, preview what it WOULD do (the engine's dry run, parsed by the
/// same parsers the log panes use), review every item, then apply behind an
/// explicit confirmation. The app never applies anything unreviewed.
struct ActionsSettingsView: View {

    enum Cleaner: String, Hashable, CaseIterable {
        case memoryClean, reclaim, storageClean, janitor

        /// The two storage-shaped cleaners share the review renderer.
        var isStorageShaped: Bool { self == .storageClean || self == .janitor }

        /// Can the user get it back? Only the janitor uses the Trash; the
        /// storage cleaner deletes, and stopping a process is not undoable
        /// (the command can be re-run, which is not the same thing).
        var isRecoverable: Bool { self == .janitor }

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
                "Closes helper processes whose parent session already died, and dev servers idle more than 24 hours. Protected apps are never touched."
            case .reclaim:
                "Sweeps EVERY reclaimable dev process at once — no age threshold, a wider net than the guard uses. Live AI sessions are exempt; protected apps are never touched."
            case .storageClean:
                "Removes stale build caches; in deep mode also downloaded code for projects you haven't touched lately (node_modules), package-manager caches (npm's entire cache), all unused container images, and Time Machine snapshot thinning. Anything touched recently is skipped."
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

    /// One prior run of the selected cleaner, parsed — the Actions history
    /// backfill (the logs already held every run; this surfaces them here).
    struct HistoryRun: Identifiable {
        let id: Int
        let header: String
        let reap: ReapRun?
        let storage: StorageCleanRun?
    }

    @Binding var preselect: String?
    @State private var cleaner: Cleaner = .memoryClean
    @State private var phase: Phase = .idle
    /// Rows the user unticked in the review. Stored as the *exclusion* set so
    /// a fresh preview starts with everything approved, which is what the
    /// preview→apply flow has always implied.
    @State private var deselected: Set<String> = []
    @State private var reapRun: ReapRun?
    @State private var storageRun: StorageCleanRun?
    @State private var confirmingApply = false
    @State private var sortByName = false
    @State private var history: [HistoryRun] = []
    @State private var lastOutput = ""
    /// Storage only: deep mode adds stale node_modules + TM snapshot report
    /// (the engine's --mode deep), vs daily's build-caches-only pass.
    @State private var storageDeep = false

    private var modeArgs: [String] {
        cleaner == .storageClean && storageDeep ? ["--mode", "deep"] : []
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
                    BadgeCapsule(text: cleaner.isRecoverable ? "GOES TO TRASH" : "PERMANENT",
                                 color: cleaner.isRecoverable ? .orange : .red)
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
            }
            controlSection
            reviewSections
            historySection
        }
        .onChange(of: cleaner) {
            resetToIdle()
            Task { await loadHistory() }
        }
        .onChange(of: preselect) { consumePreselect() }
        .task {
            consumePreselect()
            await loadHistory()
        }
        .confirmationDialog(applyPrompt, isPresented: $confirmingApply, titleVisibility: .visible) {
            Button(applyButtonTitle, role: .destructive) {
                Task { await apply() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The first sentence must say whether this can be taken back.
            // "Everything is logged" was doing that job badly while storage
            // clean does rm -rf and an Undo row sits three rows away.
            Text(cleaner.isRecoverable
                 ? "These move to the Trash, so you can put them back — from the Undo screen or from Finder. Everything is logged; protected lists always win."
                 : "This is PERMANENT — these files are deleted, not moved to the Trash, and Undo cannot bring them back. They are rebuildable: your tools recreate them when needed. Everything is logged; protected lists always win.")
        }
    }

    /// Applies a deep-link request once, then clears it — so re-delivery to
    /// an already-visible pane still works and nothing leaks to next time.
    private func consumePreselect() {
        guard let raw = preselect else { return }
        preselect = nil
        if let requested = Cleaner(rawValue: raw) { cleaner = requested }
    }

    // MARK: - control row

    @ViewBuilder private var controlSection: some View {
        Section {
            switch phase {
            case .idle:
                HStack {
                    lastRunText
                    Spacer()
                    Button("See what would be cleaned") {
                        Task { await preview() }
                    }
                    .buttonStyle(.glassProminent)
                }
            case .previewing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking what could be cleaned — nothing is being changed yet…")
                        .foregroundStyle(.secondary)
                }
            case .review:
                HStack {
                    Label(reviewHeadline, systemImage: "eye")
                        .font(.callout.weight(.medium))
                    Spacer()
                    if cleaner.isStorageShaped {
                        Picker("", selection: $sortByName) {
                            Text("Size").tag(false)
                            Text("Name").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 110)
                    }
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Try again") { resetToIdle() }
                    }
                    if !lastOutput.isEmpty {
                        DisclosureGroup("Details") {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(lastOutput.split(separator: "\n").suffix(25).enumerated()),
                                        id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        Button("Copy diagnostics") {
                            let report = """
                            script: \(cleaner.script.path)
                            args: \(modeArgs.joined(separator: " "))
                            message: \(message)

                            \(lastOutput.split(separator: "\n").suffix(40).joined(separator: "\n"))
                            """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(report, forType: .string)
                        }
                        .font(.caption)
                    }
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
            }
        }
    }

    // MARK: - per-item approval
    //
    // "Apply only what you approve" was a claim about the button, not the
    // items. Deselecting a row now genuinely keeps it out of the apply: the
    // approved set is written to a file and the engine intersects its own
    // freshly-derived findings with it.

    /// A row wrapped in its own checkbox. `key` is what the engine will be
    /// given — a pid for processes, a path for files. Rows from a finished
    /// run pass nil and render plain, since there is nothing left to approve.
    /// `name` names the row for VoiceOver — the checkbox itself carries no
    /// visible label (`.labelsHidden()`), so without this it reads as an
    /// anonymous "checkbox".
    @ViewBuilder private func selectable<Content: View>(
        _ key: String?, name: String, @ViewBuilder content: () -> Content
    ) -> some View {
        if let key, phase == .review {
            HStack(spacing: Tokens.Space.s) {
                Toggle(isOn: Binding(
                    get: { !deselected.contains(key) },
                    set: { on in
                        if on { deselected.remove(key) } else { deselected.insert(key) }
                    })) { EmptyView() }
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Include \(name) in this cleanup")
                content()
                    .opacity(deselected.contains(key) ? 0.45 : 1)
            }
        } else {
            content()
        }
    }

    private var selectionBar: some View {
        HStack {
            Text(approvedCount == totalApprovable
                 ? "All \(totalApprovable) selected"
                 : "\(approvedCount) of \(totalApprovable) selected")
                .font(.callout.weight(.medium))
            Spacer()
            Button("Select all") { deselected.removeAll() }
                .disabled(deselected.isEmpty)
            Button("Select none") { deselected = Set(approvableKeys) }
                .disabled(approvedCount == 0)
        }
    }

    /// Every key that could be acted on in this run.
    private var approvableKeys: [String] {
        switch cleaner {
        case .memoryClean, .reclaim: dryReapItems.compactMap { $0.pid.map(String.init) }
        case .storageClean, .janitor:
            storageRun?.items.filter { $0.status == .dry }.map(\.path) ?? []
        }
    }

    private var totalApprovable: Int { approvableKeys.count }
    private var approvedCount: Int { approvableKeys.filter { !deselected.contains($0) }.count }

    /// Writes the approved keys to a temp file and returns the engine flag.
    /// Nothing deselected → no flag at all, so the common case runs exactly
    /// the command it always did.
    private func approvalArgs() -> [String] {
        guard !deselected.isEmpty else { return [] }
        let approved = approvableKeys.filter { !deselected.contains($0) }
        let file = FileManager.default.temporaryDirectory
            .appending(path: "mac-analyzers-approved-\(UUID().uuidString).txt")
        guard (try? approved.joined(separator: "\n")
            .write(to: file, atomically: true, encoding: .utf8)) != nil else { return [] }
        switch cleaner {
        case .memoryClean, .reclaim: return ["--only-pids", file.path]
        case .storageClean, .janitor: return ["--only-paths", file.path]
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

    /// A selection count now, not a "was anything found" count — deselect
    /// everything and Apply is correctly unavailable.
    private var hasAnythingToApply: Bool { approvedCount > 0 }

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
        guard FileManager.default.isExecutableFile(atPath: cleaner.script.path) else {
            phase = .failed("The cleaning tools aren't installed on this Mac (expected \(cleaner.script.path)).")
            return
        }
        phase = .previewing
        let result = await ActionRunner.run(script: cleaner.script, args: ["--dry-run"] + modeArgs)
        guard result.exitCode == 0 else {
            lastOutput = result.output
            phase = .failed(Self.explain(exitCode: result.exitCode, verb: "preview"))
            return
        }
        lastOutput = result.output
        parseLatestRun()
        phase = .review
    }

    /// Exit codes as sentences. "exited 127" tells a user nothing.
    static func explain(exitCode: Int32, verb: String) -> String {
        switch exitCode {
        case 127: "Couldn't \(verb): the cleaning script wasn't found where the app expects it."
        case 126: "Couldn't \(verb): macOS blocked running the script (permissions)."
        case 78: "Couldn't \(verb): the engine refused to start because a setting is invalid — check your protected-apps list."
        case 2: "Couldn't \(verb): the script rejected the options the app passed."
        default: "Couldn't \(verb) — the script stopped with code \(exitCode)."
        }
    }

    private func apply() async {
        phase = .applying
        let result = await ActionRunner.run(script: cleaner.script,
                                            args: ["--apply"] + modeArgs + approvalArgs())
        lastOutput = result.output
        guard result.exitCode == 0 else {
            phase = .failed(Self.explain(exitCode: result.exitCode, verb: "apply"))
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

    private struct ReviewGroup {
        let project: String
        let items: [StoragePathItem]
        let total: Int64
    }

    private func reviewGroups(from run: StorageCleanRun) -> [ReviewGroup] {
        let visible = run.items.filter {
            $0.status == .dry || $0.status == .deleted || $0.status == .trashed
        }
        var groups = Dictionary(grouping: visible, by: \.project).map { key, value in
            let items: [StoragePathItem]
            if sortByName {
                items = value.sorted {
                    $0.cacheKind.localizedCaseInsensitiveCompare($1.cacheKind) == .orderedAscending
                }
            } else {
                items = value.sorted { $0.sizeBytes > $1.sizeBytes }
            }
            return ReviewGroup(project: key, items: items,
                               total: value.map(\.sizeBytes).reduce(0, +))
        }
        if sortByName {
            groups.sort {
                $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
            }
        } else {
            groups.sort { $0.total > $1.total }
        }
        return groups
    }

    // MARK: - path rows (icons + Finder reveal)

    /// Real file/folder icon + Show in Finder — the same first-class
    /// treatment the memory lists give apps.
    private func pathRow(_ item: StoragePathItem) -> some View {
        let exists = FileManager.default.fileExists(atPath: item.path)
        return HStack(spacing: 6) {
            DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                     title: item.cacheKind,
                     subtitle: item.path,
                     trailing: ByteSize.format(item.sizeBytes),
                     badge: item.status == .deleted ? ("DELETED", .red)
                         : item.status == .trashed ? ("TRASHED", .orange)
                         : ("WOULD REMOVE", .blue))
            if exists {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: item.path)])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
        }
    }

    // MARK: - history (the backfill: every prior run, parsed)

    @ViewBuilder private var historySection: some View {
        if !history.isEmpty {
            Section("Previous runs") {
                ForEach(history) { run in
                    DisclosureGroup {
                        historyCards(run)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.header)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if let summary = run.reap?.summary ?? run.storage?.summary {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func historyCards(_ run: HistoryRun) -> some View {
        if let reap = run.reap {
            ForEach(reap.allItems.prefix(15)) { item in
                DataCard(symbol: "terminal", color: statusColor(item.status),
                         title: item.friendlyName,
                         subtitle: item.description,
                         trailing: item.mb.map { "\($0) MB" },
                         badge: badge(for: item.status))
            }
        }
        if let storage = run.storage {
            ForEach(storage.items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(15)) { item in
                pathRow(item)
            }
        }
    }

    private func loadHistory() async {
        let logKind = cleaner.logKind
        let storageShaped = cleaner.isStorageShaped
        await awaitLoad({
            LogParser.runs(for: logKind).prefix(10).enumerated().map { index, run in
                HistoryRun(id: index, header: run.header,
                           reap: storageShaped ? nil
                               : ReapParser.parse(runHeader: run.header, lines: run.lines),
                           storage: storageShaped
                               ? StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
                               : nil)
            }
        }) { history = $0 }
    }

    private func resetToIdle() {
        phase = .idle
        reapRun = nil
        storageRun = nil
        deselected.removeAll()
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
