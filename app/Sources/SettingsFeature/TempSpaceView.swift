import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Temp & Agents pane: what is really in /tmp, /var and the AI agents'
/// folders. The insight surface — mounted disk images told apart from real
/// disk use (with Eject), every row's verdict and why, agent history and
/// macOS-managed areas sized but never touched. Clearing goes through
/// Actions (`actions:tempClean`), the one reviewed apply flow, so untick and
/// the approved-set contract work exactly as they do for every cleaner.
struct TempSpaceView: View {

    private enum Filter: String, CaseIterable {
        case ready = "Ready"
        case leftAlone = "Left alone"
        case sized = "Sized only"
        case all = "All"
    }

    /// Drives the small status line under the action row only — the lists
    /// stay visible while a script runs (same as SpotlightAuditView).
    private enum RunPhase: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    @State private var run: TempCleanRun?
    @State private var filter: Filter = .ready
    @State private var runPhase: RunPhase = .idle
    /// Sections showing every row rather than the biggest few.
    @State private var expanded: Set<String> = []
    @State private var ejecting: TempMount?

    private static let collapsedRows = 12

    var body: some View {
        PaneScaffold(symbol: "tray.full", color: .mint, title: "Temp & Agents",
                     caption: "What /tmp, /var and your AI agents' folders really hold — disk images told apart from real use, every verdict explained. Clearing is reviewed in Actions; nothing open, recent, live or someone else's is ever touched.") {
            Section {
                HStack {
                    Spacer(minLength: 8)
                    Button("Run audit") { Task { await runAudit() } }
                        .disabled(isBusy)
                        .help("Runs temp-clean.sh --dry-run and refreshes this pane. Changes nothing.")
                    Button("Review & clean…") { openActions() }
                        .buttonStyle(.glassProminent)
                        .disabled(isBusy || (run?.readyItems.isEmpty ?? true))
                        .help("Opens Actions › Temp & Agents: preview, untick anything you want kept, then move to the Trash (or delete permanently).")
                    Button("Open in TextEdit") { GuardControl.openLog(AnalyzersPaths.tempCleanLog) }
                    Button {
                        Task { await load(force: true) }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                        .accessibilityLabel("Refresh")
                }
                statusLine
                if let run {
                    HStack(spacing: 6) {
                        BadgeCapsule(text: run.dryRun ? "AUDIT" : (run.permanent ? "DELETED" : "TRASHED"),
                                     color: run.dryRun ? .blue : (run.permanent ? .red : .orange))
                        Text(run.summary ?? run.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let run {
                overviewSection(run)
                if !run.mounts.isEmpty { mountsSection(run) }
                itemSections(run)
            } else {
                Section {
                    Text("No audit yet — Run audit to see what /tmp, /var and your AI agents' folders hold. Nothing is changed.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await load() }
        .confirmationDialog(ejectPrompt, isPresented: Binding(
            get: { ejecting != nil }, set: { if !$0 { ejecting = nil } }),
                            titleVisibility: .visible) {
            Button("Eject") {
                if let mount = ejecting { Task { await eject(mount) } }
            }
            Button("Cancel", role: .cancel) { ejecting = nil }
        } message: {
            Text("Closes the disk image — nothing is deleted, and you can open the image file again any time. If something is still reading from it, macOS refuses and nothing changes.")
        }
    }

    @ViewBuilder private var statusLine: some View {
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
    }

    private var isBusy: Bool {
        if case .running = runPhase { return true }
        return false
    }

    private var ejectPrompt: String {
        guard let mount = ejecting else { return "Eject disk image?" }
        let name = (mount.mountPoint as NSString).lastPathComponent
        return mount.alsoEjects.isEmpty
            ? "Eject \(name)?"
            : "Eject \(name) and \(mount.alsoEjects.count) image\(mount.alsoEjects.count == 1 ? "" : "s") opened from inside it?"
    }

    // MARK: - overview

    @ViewBuilder private func overviewSection(_ run: TempCleanRun) -> some View {
        Section("Where the space is") {
            if let free = run.freeSpace {
                DataCard(symbol: "internaldrive", color: .blue,
                         title: "Free space", subtitle: "on this Mac's disk", trailing: free)
            }
            DataCard(symbol: "tray.full", color: .mint,
                     title: "Temp on disk", subtitle: "/tmp, your temp folder and /var/tmp",
                     trailing: run.tempOnDisk)
            if let inside = run.insideImagesBytes, inside > 0 {
                DataCard(symbol: "opticaldiscdrive", color: .purple,
                         title: "Inside mounted disk images",
                         subtitle: "Not on your disk — a plain du would report \(run.plainDu ?? "more")",
                         trailing: run.insideImages)
            }
            DataCard(symbol: "sparkles", color: .orange,
                     title: "AI agent folders", subtitle: agentSubtitle(run),
                     trailing: run.agentFolders)
            DataCard(symbol: "checkmark.circle", color: .green,
                     title: "Ready to clear",
                     subtitle: run.readyItems.isEmpty
                         ? "Nothing qualifies right now"
                         : "\(run.readyItems.reduce(0) { $0 + $1.count }) item(s) — review and untick in Actions",
                     trailing: ByteSize.format(run.readyBytes))
            if let rules = run.rulesLine {
                Text(rules)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let selfClean = run.selfCleanLine {
                Text(selfClean)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func agentSubtitle(_ run: TempCleanRun) -> String {
        var parts: [String] = []
        if let n = run.liveClaudeSessions { parts.append("\(n) live Claude Code session\(n == 1 ? "" : "s")") }
        if let codex = run.codexRunning { parts.append(codex ? "Codex running" : "Codex closed") }
        if let claude = run.claudeAppRunning { parts.append(claude ? "Claude app running" : "Claude app closed") }
        return parts.isEmpty ? "Claude Code, Codex, Claude app, npx tools" : parts.joined(separator: " · ")
    }

    // MARK: - mounted disk images

    @ViewBuilder private func mountsSection(_ run: TempCleanRun) -> some View {
        Section {
            ForEach(run.mounts) { mount in
                mountRow(mount)
            }
        } header: {
            Text("Mounted disk images")
        } footer: {
            Text("Their contents are not on your disk. A file that backs an image can't free space until the image is ejected — clearing it in Actions ejects it first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mountRow(_ mount: TempMount) -> some View {
        let badge: (String, Color) = switch mount.status {
        case .mounted: mount.imageLivesInTemp ? ("IMAGE IN TEMP", .orange) : ("MOUNTED", .purple)
        case .ejected: ("EJECTED", .green)
        case .ejectFailed: ("EJECT FAILED", .red)
        }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                DataCard(symbol: "opticaldiscdrive", color: .purple,
                         title: (mount.mountPoint as NSString).lastPathComponent,
                         subtitle: "from \(mount.imagePath)",
                         trailing: ByteSize.format(mount.sizeBytes), badge: badge)
                    .help(mount.mountPoint)
                if mount.status == .mounted {
                    Button("Eject…") { ejecting = mount }
                        .controlSize(.small)
                        .disabled(isBusy)
                }
                if FileManager.default.fileExists(atPath: mount.imagePath) {
                    revealButton(mount.imagePath, help: "Show the image file in Finder")
                }
            }
            if !mount.alsoEjects.isEmpty {
                Text("Also ejects: " + mount.alsoEjects.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(mount.details.filter { !$0.contains("lives in temp") && !$0.hasPrefix("ejecting it also") },
                    id: \.self) { detail in
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - rows, grouped by where they live

    @ViewBuilder private func itemSections(_ run: TempCleanRun) -> some View {
        Section {
            FilterChipsBar(
                chips: Filter.allCases.map { f in
                    .init(f, f.rawValue, count: matching(f, run).count, color: chipColor(f))
                },
                selection: $filter
            )
        }
        let visible = matching(filter, run)
        if visible.isEmpty {
            Section {
                Label(emptyText, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(run.sections, id: \.self) { section in
                let rows = visible.filter { $0.section == section }.sorted { $0.sizeBytes > $1.sizeBytes }
                if !rows.isEmpty {
                    Section("\(section) — \(ByteSize.format(rows.reduce(0) { $0 + $1.sizeBytes }))") {
                        let showAll = expanded.contains(section) || rows.count <= Self.collapsedRows
                        ForEach(showAll ? rows : Array(rows.prefix(Self.collapsedRows))) { item in
                            itemRow(item)
                        }
                        if rows.count > Self.collapsedRows {
                            Button(showAll ? "Show fewer" : "Show all \(rows.count)") {
                                if showAll { expanded.remove(section) } else { expanded.insert(section) }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        switch filter {
        case .ready: "Nothing is ready to clear — everything here is recent, in use, or not yours."
        case .leftAlone: "Nothing was left alone."
        case .sized: "No history or managed areas found."
        case .all: "Nothing found."
        }
    }

    private func itemRow(_ item: TempItem) -> some View {
        let exists = !item.isGroup && FileManager.default.fileExists(atPath: item.path)
        return HStack(spacing: 6) {
            Group {
                if exists {
                    DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                             title: item.displayName, subtitle: subtitle(item),
                             trailing: ByteSize.format(item.sizeBytes), badge: badge(item))
                } else {
                    DataCard(symbol: item.isGroup ? "square.stack.3d.up" : "doc",
                             color: badge(item).1,
                             title: item.displayName, subtitle: subtitle(item),
                             trailing: ByteSize.format(item.sizeBytes), badge: badge(item))
                }
            }
            .help(item.path)
            if item.isGroup {
                revealButton(item.parentPath, help: "Show the folder in Finder")
            } else if exists {
                revealButton(item.path, help: "Show in Finder")
            }
        }
        // acted-on or vanished rows stay listed (it is still what happened)
        // but read as inert, the weight Actions gives a deselected row
        .opacity(item.wasActedOn || (!item.isGroup && !exists) ? 0.55 : 1)
    }

    private func subtitle(_ item: TempItem) -> String {
        var parts: [String] = []
        if item.isGroup { parts.append("\(item.count) items") }
        if !item.ejects.isEmpty {
            parts.append("ejects \(item.ejects.count) disk image\(item.ejects.count == 1 ? "" : "s") first")
        }
        if let reason = item.reason { parts.append(reason) }
        return parts.isEmpty ? item.path : parts.joined(separator: " · ")
    }

    private func badge(_ item: TempItem) -> (String, Color) {
        switch item.status {
        case .dry: ("READY", .blue)
        case .trashed: ("TRASHED", .orange)
        case .deleted: ("DELETED", .red)
        case .failed: ("FAILED", .red)
        case .skip: ("UNTICKED", .gray)
        case .recent: ("RECENT", .teal)
        case .inUse: ("IN USE", .green)
        case .protected: ("PROTECTED", .green)
        case .notYours: ("NOT YOURS", .gray)
        case .keep: ("YOUR KEEP LIST", .gray)
        case .system: ("SYSTEM", .gray)
        case .history: ("HISTORY", .purple)
        case .kept: ("KEPT", .gray)
        case .managed: ("MANAGED", .gray)
        }
    }

    private func matching(_ f: Filter, _ run: TempCleanRun) -> [TempItem] {
        switch f {
        case .ready:
            run.items.filter { $0.isReady || $0.wasActedOn || $0.status == .failed || $0.status == .skip }
        case .leftAlone:
            run.items.filter {
                [.recent, .inUse, .protected, .notYours, .keep, .system].contains($0.status)
            }
        case .sized: run.items.filter(\.isSizedOnly)
        case .all: run.items
        }
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .ready: .blue
        case .leftAlone: .green
        case .sized: .purple
        case .all: .mint
        }
    }

    private func revealButton(_ path: String, help: String) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: { Image(systemName: "magnifyingglass.circle") }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
    }

    // MARK: - actions

    private func runAudit() async {
        runPhase = .running("Auditing /tmp, /var and agent folders — nothing is being changed…")
        let result = await ActionRunner.run(script: AnalyzersPaths.tempCleanScript, args: ["--dry-run"])
        guard result.exitCode == 0 else {
            runPhase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "run the audit"))
            return
        }
        runPhase = .done("Audit complete.")
        await load(force: true)
    }

    /// `--eject <mountpoint>`: the engine ejects dependents first (an image
    /// opened from inside this one), never forced, then re-audits — so the
    /// pane reloads into a run that already reflects the eject.
    private func eject(_ mount: TempMount) async {
        ejecting = nil
        let name = (mount.mountPoint as NSString).lastPathComponent
        runPhase = .running("Ejecting \(name)…")
        let result = await ActionRunner.run(script: AnalyzersPaths.tempCleanScript,
                                            args: ["--eject", mount.mountPoint])
        guard result.exitCode == 0 else {
            runPhase = .failed(ExitExplanation.explain(exitCode: result.exitCode, verb: "eject \(name)"))
            return
        }
        await load(force: true)
        let after = run?.mounts.first { $0.mountPoint == mount.mountPoint }
        if after?.status == .ejectFailed {
            runPhase = .failed("Couldn't eject \(name) — something is still reading from it. Close it there, then try again.")
        } else {
            runPhase = .done("Ejected \(name).")
        }
    }

    private func openActions() {
        NotificationCenter.default.post(
            name: NotifyChannel.openPaneInternal, object: nil,
            userInfo: ["target": "actions:tempClean"])
    }

    // MARK: - load

    /// `force` bypasses the LoadCoordinator TTL right after a script run —
    /// the log just changed and the cached parse would otherwise be served.
    private func load(force: Bool = false) async {
        await awaitLoad({
            LogParser.runs(for: .tempSpace).first.map {
                TempCleanParser.parse(runHeader: $0.header, lines: $0.lines)
            }
        }, ttl: force ? 0 : 3) { run = $0 }
    }
}
