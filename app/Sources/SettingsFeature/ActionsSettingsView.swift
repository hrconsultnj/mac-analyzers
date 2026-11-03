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
        case memoryClean, reclaim, storageClean, janitor, tempClean

        /// The two storage-shaped cleaners share the review renderer.
        var isStorageShaped: Bool { self == .storageClean || self == .janitor }

        /// Can the user get it back? The janitor and temp clean use the Trash
        /// (temp clean unless permanent is chosen — see `recoverableNow`); the
        /// storage cleaner deletes, and stopping a process is not undoable
        /// (the command can be re-run, which is not the same thing).
        var isRecoverable: Bool { self == .janitor || self == .tempClean }

        var title: String {
            switch self {
            case .memoryClean: "Memory Clean"
            case .reclaim: "Memory Reclaim"
            case .storageClean: "Storage Clean"
            case .janitor: "Janitor"
            case .tempClean: "Temp & Agents"
            }
        }

        var blurb: String {
            switch self {
            case .memoryClean:
                "Closes helper processes whose parent session already died, and dev servers idle more than 24 hours. Protected apps are never touched."
            case .reclaim:
                "Sweeps EVERY reclaimable dev process at once — no age threshold, a wider net than the guard uses. Live AI sessions are exempt; protected apps are never touched."
            case .storageClean:
                "Removes stale build caches and trims oversized Turborepo caches; in deep mode also downloaded code for projects you haven't touched lately (node_modules), idle git worktrees (never main — uncommitted work is parked first), package-manager caches (npm's entire cache), the app and tool caches you enabled in Settings › Storage, and releases Time Machine snapshot space so the freed space shows up. Anything touched recently or in use is skipped."
            case .janitor:
                "Moves stale Downloads and old screenshots to the Trash — recoverable, keep-patterns honored, folders reviewed as units."
            case .tempClean:
                "Clears idle leftovers in /tmp, your temp folder and /var/tmp, plus AI-agent scratch (Claude Code, Codex, the Claude app, npx-run tools). Never anything open, recent, live, or someone else's; agent history and settings are never touched. A file behind a mounted disk image ejects it first."
            }
        }

        var symbol: String {
            switch self {
            case .memoryClean: "memorychip"
            case .reclaim: "arrow.3.trianglepath"
            case .storageClean: "internaldrive.fill"
            case .janitor: "trash"
            case .tempClean: "tray.full"
            }
        }

        var color: Color {
            switch self {
            case .memoryClean: .blue
            case .reclaim: .teal
            case .storageClean: .indigo
            case .janitor: .orange
            case .tempClean: .mint
            }
        }

        var script: URL {
            switch self {
            case .memoryClean: AnalyzersPaths.memoryCleanScript
            case .reclaim: AnalyzersPaths.reclaimScript
            case .storageClean: AnalyzersPaths.storageCleanScript
            case .janitor: AnalyzersPaths.janitorScript
            case .tempClean: AnalyzersPaths.tempCleanScript
            }
        }

        var logKind: LogKind {
            switch self {
            case .memoryClean: .memoryClean
            case .reclaim: .reclaim
            case .storageClean: .storageClean
            case .janitor: .janitor
            case .tempClean: .tempSpace
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
        let temp: TempCleanRun?
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
    @State private var tempRun: TempCleanRun?
    @State private var confirmingApply = false
    /// Temp only: the second, plain-words confirmation a permanent delete
    /// gets on top of the usual one.
    @State private var confirmingPermanent = false
    @State private var sortByName = false
    @State private var history: [HistoryRun] = []
    @State private var lastOutput = ""
    /// Storage only: deep mode adds stale node_modules + TM snapshot report
    /// (the engine's --mode deep), vs daily's build-caches-only pass.
    @State private var storageDeep = false
    /// Temp only: delete instead of moving to the Trash (the engine's --permanent).
    @State private var tempPermanent = false

    private var modeArgs: [String] {
        switch cleaner {
        case .storageClean: storageDeep ? ["--mode", "deep", "--prune-snapshots"] : []
        case .tempClean: tempPermanent ? ["--permanent"] : []
        case .memoryClean, .reclaim, .janitor: []
        }
    }

    /// Recoverable for THIS run — temp clean stops being so when permanent
    /// is chosen, and every label and confirmation must say which.
    private var recoverableNow: Bool {
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
                if cleaner == .tempClean && tempPermanent {
                    confirmingPermanent = true
                } else {
                    Task { await apply() }
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
                Task { await apply() }
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
                    if cleaner.isStorageShaped || cleaner == .tempClean {
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
            case .tempClean:
                tempReviewSections
            }
        }
    }

    // MARK: - temp review (grouped by where things live, like the log pane)

    @ViewBuilder private var tempReviewSections: some View {
        if let run = tempRun {
            if phase == .review, !run.readyItems.isEmpty {
                Section { selectionBar }
            }
            let ejecting = run.readyItems.filter { !$0.ejects.isEmpty && !deselected.contains($0.path) }
            if phase == .review, !ejecting.isEmpty {
                Section {
                    ForEach(ejecting) { item in
                        DataCard(symbol: "opticaldiscdrive", color: .purple,
                                 title: "\(item.displayName) backs mounted disk images",
                                 subtitle: "Applying ejects them first (never forced): "
                                     + item.ejects.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "),
                                 badge: ("EJECTS FIRST", .purple))
                    }
                }
            }
            let shown = run.items.filter { $0.isReady || $0.wasActedOn || $0.status == .failed }
            ForEach(run.sections, id: \.self) { section in
                let rows = shown.filter { $0.section == section }.sorted {
                    sortByName
                        ? $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                        : $0.sizeBytes > $1.sizeBytes
                }
                if !rows.isEmpty {
                    Section("\(section) — \(ByteSize.format(rows.reduce(0) { $0 + $1.sizeBytes }))") {
                        ForEach(rows) { item in
                            selectable(item.isReady ? item.path : nil, name: item.displayName) {
                                tempRow(item)
                            }
                        }
                    }
                }
            }
            let leftAlone = run.items.filter {
                [.recent, .inUse, .protected, .notYours].contains($0.status)
            }.reduce(0) { $0 + $1.count }
            if leftAlone > 0 {
                Section {
                    Label("\(leftAlone) item\(leftAlone == 1 ? "" : "s") left alone this run — recent, in use, a live session, or not yours. Logs › Temp & Agents says why for each.",
                          systemImage: "shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tempRow(_ item: TempItem) -> some View {
        let exists = !item.isGroup && FileManager.default.fileExists(atPath: item.path)
        var bits: [String] = []
        if item.isGroup { bits.append("\(item.count) items") }
        if let reason = item.reason { bits.append(reason) }
        let subtitle = bits.isEmpty ? item.path : bits.joined(separator: " · ")
        let badge: (String, Color) = switch item.status {
        case .trashed: ("TRASHED", .orange)
        case .deleted: ("DELETED", .red)
        case .failed: ("FAILED", .red)
        default: recoverableNow ? ("WOULD TRASH", .blue) : ("WOULD DELETE", .red)
        }
        return HStack(spacing: 6) {
            Group {
                if exists {
                    DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                             title: item.displayName, subtitle: subtitle,
                             trailing: ByteSize.format(item.sizeBytes), badge: badge)
                } else {
                    DataCard(symbol: item.isGroup ? "square.stack.3d.up" : "doc", color: badge.1,
                             title: item.displayName, subtitle: subtitle,
                             trailing: ByteSize.format(item.sizeBytes), badge: badge)
                }
            }
            .help(item.path)
            if exists || item.isGroup {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: item.isGroup ? item.parentPath : item.path)])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
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
        case .tempClean:
            tempRun?.readyItems.map(\.path) ?? []
        }
    }

    /// Bytes still ticked in a temp review — what the permanent alert names.
    private var tempSelectedBytes: Int64 {
        tempRun?.readyItems.filter { !deselected.contains($0.path) }
            .reduce(0) { $0 + $1.sizeBytes } ?? 0
    }

    private var totalApprovable: Int { approvableKeys.count }
    private var approvedCount: Int { approvableKeys.filter { !deselected.contains($0) }.count }

    /// Writes the approved keys to a temp file and returns the engine flag.
    /// Nothing deselected → no flag at all, so the common case runs exactly
    /// the command it always did. Temp clean always sends the list: temp
    /// folders change by the minute, and an item that crosses the age line
    /// between preview and apply must not ride along unreviewed.
    private func approvalArgs() -> [String] {
        guard !deselected.isEmpty || cleaner == .tempClean else { return [] }
        let approved = approvableKeys.filter { !deselected.contains($0) }
        let file = FileManager.default.temporaryDirectory
            .appending(path: "mac-analyzers-approved-\(UUID().uuidString).txt")
        guard (try? approved.joined(separator: "\n")
            .write(to: file, atomically: true, encoding: .utf8)) != nil else { return [] }
        switch cleaner {
        case .memoryClean, .reclaim: return ["--only-pids", file.path]
        case .storageClean, .janitor, .tempClean: return ["--only-paths", file.path]
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
        case .tempClean:
            let bytes = tempRun?.readyBytes ?? 0
            return bytes == 0
                ? "Nothing ready to clear."
                : recoverableNow
                    ? "Would move \(ByteSize.format(bytes)) to the Trash"
                    : "Would delete \(ByteSize.format(bytes)) permanently"
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
        case .tempClean:
            recoverableNow ? "Apply — trash \(ByteSize.format(tempSelectedBytes))"
                           : "Apply — delete \(ByteSize.format(tempSelectedBytes))"
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
        case .tempClean:
            recoverableNow
                ? "Move the ticked items (\(ByteSize.format(tempSelectedBytes))) to the Trash?"
                : "Permanently delete the ticked items (\(ByteSize.format(tempSelectedBytes)))?"
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
        case .tempClean:
            let acted = tempRun?.actedBytes ?? 0
            if acted == 0 { return "Done — nothing was cleared." }
            return tempPermanent
                ? "Deleted \(ByteSize.format(acted)) permanently. Receipts in the log."
                : "Moved \(ByteSize.format(acted)) to the Trash — restore from Undo; the space returns when the Trash is emptied."
        }
    }

    private func parseLatestRun() {
        guard let latest = LogParser.runs(for: cleaner.logKind).first else {
            reapRun = nil
            storageRun = nil
            tempRun = nil
            return
        }
        switch cleaner {
        case .memoryClean, .reclaim:
            reapRun = ReapParser.parse(runHeader: latest.header, lines: latest.lines)
        case .storageClean, .janitor:
            storageRun = StorageCleanParser.parse(runHeader: latest.header, lines: latest.lines)
        case .tempClean:
            tempRun = TempCleanParser.parse(runHeader: latest.header, lines: latest.lines)
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
                            if let summary = run.reap?.summary ?? run.storage?.summary ?? run.temp?.summary {
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
        if let temp = run.temp {
            let rows = temp.dryRun ? temp.readyItems : temp.actedItems
            ForEach(rows.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(15)) { item in
                tempRow(item)
            }
        }
    }

    private func loadHistory() async {
        let logKind = cleaner.logKind
        let storageShaped = cleaner.isStorageShaped
        let tempShaped = cleaner == .tempClean
        await awaitLoad({
            LogParser.runs(for: logKind).prefix(10).enumerated().map { index, run in
                HistoryRun(id: index, header: run.header,
                           reap: storageShaped || tempShaped ? nil
                               : ReapParser.parse(runHeader: run.header, lines: run.lines),
                           storage: storageShaped
                               ? StorageCleanParser.parse(runHeader: run.header, lines: run.lines)
                               : nil,
                           temp: tempShaped
                               ? TempCleanParser.parse(runHeader: run.header, lines: run.lines)
                               : nil)
            }
        }) { history = $0 }
    }

    private func resetToIdle() {
        phase = .idle
        reapRun = nil
        storageRun = nil
        tempRun = nil
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
