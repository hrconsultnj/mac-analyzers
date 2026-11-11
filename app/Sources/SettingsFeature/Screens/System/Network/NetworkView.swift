import AppKit
import AnalyzersKit
import SwiftUI

/// Network: which programs have moved the most data, from the newest snapshot
/// (or an older one picked from History). nettop's counters are totals since
/// each program started, so this is the "who has been phoning home" ledger,
/// not a live speed meter. Observation only; nothing is blocked.
///
/// One job per file next to it:
///   NetworkModel.swift         the snapshots and the job that takes one
///   NetworkTable.swift         the table
///   NetworkInspector.swift     the selected program in full
///   NetworkHistoryList.swift   the History scope: a day-grouped list
///
/// Toolbar, in the order it gives up space: the scope control and Take
/// Snapshot stay; Stop moves into the system's overflow first; search folds to
/// its icon.
struct NetworkView: View {

    enum Scope: String, CaseIterable, Identifiable {
        case snapshot, history
        var id: String { rawValue }
        var title: String { self == .snapshot ? Names.NetworkScope.snapshot : Names.NetworkScope.history }
        var symbol: String { self == .snapshot ? "network" : "clock.arrow.circlepath" }
    }

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var model = NetworkModel()
    @State private var scope: Scope = .snapshot
    @State private var query = ""
    @State private var selection: NetworkNode.ID?
    @State private var opened: [NetworkGroup.ID: Bool] = [:]
    @State private var historySelection: NetworkSnapshotRun.ID?
    @State private var showInspector = false

    private var groups: [NetworkGroup] {
        let all = model.rows()
        let kept = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.group.localizedCaseInsensitiveContains(query)
        }
        return NetworkGroup.groups(of: kept)
    }

    private var selectedRow: NetworkProcessRow? { model.rows().first { $0.id == selection } }
    private var selectedGroup: NetworkGroup? { NetworkGroup.groups(of: model.rows()).first { $0.id == selection } }

    var body: some View {
        content
            .navigationTitle(Names.Screen.network)
            .navigationSubtitle(subtitle)
            .searchable(text: $query, prompt: "Search programs")
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                Group {
                    if let row = selectedRow {
                        NetworkInspector(row: row, onShowInFinder: { reveal(row) })
                    } else if let group = selectedGroup {
                        NetworkGroupInspector(group: group)
                    }
                }
                .inspectorColumnWidth(min: 240, ideal: 240, max: 360)
            }
            .task {
                model.adopt(from: store)
                await model.reload()
                applyPendingLink()
                // nothing saved yet: take the first one
                if model.newest == nil, !model.isTaking { model.take(in: store) }
            }
            // when the snapshot job ends, read what it wrote
            .onChange(of: model.job?.stamp) { _, stamp in
                if stamp?.stage == .succeeded { Task { await model.reload() } }
            }
            .onChange(of: selection) { showInspector = selection != nil }
            // a link opened while Network is already showing
            .onChange(of: navigator.pendingIntent) { applyPendingLink() }
    }

    @ViewBuilder private var content: some View {
        switch scope {
        case .snapshot:
            if model.viewing == nil {
                ContentUnavailableView {
                    Label(model.isTaking ? "Taking a Snapshot" : "No Snapshot Yet", systemImage: "network")
                } description: {
                    Text(model.isTaking ? "Reading what each program has sent and received."
                                        : "Take a snapshot to see which programs have been using the network.")
                }
            } else {
                NetworkTable(groups: groups, selection: $selection, opened: $opened, onShowInFinder: reveal)
                    .safeAreaInset(edge: .top, spacing: 0) { totalsBar }
            }
        case .history:
            NetworkHistoryList(snapshots: model.snapshots, selection: $historySelection,
                               onOpen: open)
        }
    }

    /// The two numbers the old screen led with, and a way back from an older snapshot.
    private var totalsBar: some View {
        HStack {
            if let viewing = model.viewing {
                Label("\(ByteSize.format(viewing.totalDownloaded)) downloaded", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Label("\(ByteSize.format(viewing.totalUploaded)) uploaded", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if model.isViewingOlder {
                Button("Show Latest") { model.viewingID = nil }
            }
            if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.bar)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScopeButtons(items: Scope.allCases, selection: $scope, title: \.title, symbol: \.symbol,
                         count: { $0 == .snapshot ? model.viewing?.processCount : model.snapshots.count })
        }
        .rank(.high)

        // the tabs show a selection; the actions are a separate group
        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .primaryAction) {
            Button { model.take(in: store); scope = .snapshot } label: {
                Label("Take Snapshot", systemImage: "arrow.clockwise")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.isTaking)
            .help("Read what every program has sent and received since it started")
        }
        .rank(.high)

        ToolbarItem(placement: .primaryAction) {
            Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                .labelStyle(.titleAndIcon)
                .disabled(!model.isTaking)
                .help("Stop the snapshot")
        }
        .rank(.low)
    }

    private var subtitle: String {
        if model.isTaking { return "Taking a snapshot…" }
        guard let viewing = model.viewing else { return "No snapshot yet" }
        let when = viewing.date.formatted(.relative(presentation: .named))
        return scope == .history
            ? "\(model.snapshots.count) saved"
            : "\(viewing.processCount) programs · \(model.isViewingOlder ? "from" : "taken") \(when)"
    }

    private func reveal(_ row: NetworkProcessRow) {
        guard let path = row.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// A deep link's request: History, the previous snapshot, or a program to open.
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: SystemGroup.network) else { return }
        if payload == "history" { scope = .history }
        if payload == "older", model.snapshots.count > 1 { model.viewingID = model.snapshots[1].id }
        if payload == "collapsed" { opened = Dictionary(uniqueKeysWithValues: NetworkGroup.groups(of: model.rows()).map { ($0.id, false) }) }
        if payload.hasPrefix("pick:"), let n = Int(payload.dropFirst("pick:".count)) {
            let ranked = NetworkGroup.groups(of: model.rows())
            if ranked.indices.contains(n) {
                selection = ranked[n].count == 1 ? ranked[n].rows[0].id : ranked[n].id
                showInspector = true
            }
        }
    }

    private func open(_ run: NetworkSnapshotRun) {
        model.viewingID = run.id
        selection = nil
        scope = .snapshot
    }
}
