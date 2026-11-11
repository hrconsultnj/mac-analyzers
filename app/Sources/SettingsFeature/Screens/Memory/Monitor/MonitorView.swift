import SwiftUI
import AnalyzersKit
import UIComponents

/// Monitor: the table IS the screen. Every running process, grouped by the app
/// or tool it belongs to, in one hierarchical table that fills the window —
/// open an app to see its parts, open a part to see its processes, and for
/// command-line tools see each separate program on its own.
///
/// One job per file next to it:
///   MonitorModel.swift       the rows between refreshes: values update in place, order only when asked
///   MonitorOutline.swift     the table — the one file that knows how it is drawn (the app's `OutlineTable`)
///   MonitorProbe.swift       the same table driven headless, for `scripts/monitor-probe.sh`
///   MonitorCategory.swift    the tabs, in the shape the shared tabs control takes
///   MonitorView+Strip.swift  the memory bar above the table
///   MonitorView+Toolbar.swift  lens, refresh, Stop, inspector toggle
///   MonitorView+Lenses.swift   the Energy and Disk I/O tables
///   MonitorInspector.swift   what the selected row is, and the memory legend when nothing is selected
///   MonitorStopFlow.swift    confirmations, the stop itself, and the word after
///   MonitorStopSheet.swift   the list a group Stop with several programs opens
///   AnalyzersKit/Memory/Monitor/  the rows, built and merged so the probe can print them
struct MonitorView: View {

    /// The category tabs. The raw values are the keys a deep link and the remembered tab use.
    enum Scope: String, CaseIterable, Identifiable {
        case everything, apps, tools, system
        var id: String { rawValue }
        var category: CensusGroup.Category? {
            switch self {
            case .everything: nil
            case .apps: .apps
            case .tools: .tools
            case .system: .system
            }
        }
    }

    @Environment(Navigator.self) var navigator
    @State var model = MonitorModel()
    @State var selection: MonitorRow.ID?
    /// The Energy and Disk I/O tables select too (nothing reads it).
    @State var lensSelection: Int?
    @State var search = ""
    @State var scope: Scope = .everything
    @State var sortOrder: [KeyPathComparator<MonitorRow>] = [KeyPathComparator(\.memoryBytes, order: .reverse)]
    @State var energySort: [KeyPathComparator<EnergyEntry>] = [KeyPathComparator(\.energyNJ, order: .reverse)]
    @State var diskSort: [KeyPathComparator<DiskIOEntry>] = [KeyPathComparator(\.bytesWritten, order: .reverse)]
    /// Remembered between launches; closed to begin with, so the table has the window.
    @AppStorage("monitor.inspectorShown") var inspectorShown = false
    @State var stopFlow = MonitorStopFlow()
    @FocusState var searchFocused: Bool
    /// Shared with the menu-bar panel; 0 is Paused.
    @AppStorage("monitorRefreshSeconds") var refreshSeconds = 15

    /// The tabs: each with its symbol, name and how many groups are in it.
    var scopeItems: [ScopeTabItem<Scope>] {
        let categories = MonitorCategory.categories(of: model.rows)
        func item(_ scope: Scope) -> ScopeTabItem<Scope> {
            let match = categories.first { $0.category == scope.category }
            return ScopeTabItem(value: scope, title: match?.title ?? Names.Monitor.everything,
                                symbol: match?.symbol ?? "square.stack.3d.up",
                                count: model.hasLoaded ? match?.groups : nil)
        }
        return Scope.allCases.map(item)
    }

    var visibleRows: [MonitorRow] {
        MonitorTree.filtered(model.rows, category: scope.category, search: search)
    }

    var body: some View {
        DataScreen(title: Names.Screen.monitor, subtitle: subtitle) { content }
            .safeAreaInset(edge: .top, spacing: 0) { strip }
            .inspector(isPresented: $inspectorShown) {
                MonitorInspector(model: model, row: model.row(selection),
                                 begin: stopFlow.begin, showDetails: showDetails)
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
            }
            .searchable(text: $search, prompt: "Search processes")
            .scopeTabsToolbar(screen: "monitor", items: scopeItems, selection: $scope)
            .searchFocused($searchFocused)
            .toolbar { MonitorToolbar(model: model, refreshSeconds: $refreshSeconds,
                                      selected: model.row(selection), begin: stopFlow.begin,
                                      inspectorShown: $inspectorShown,
                                      refreshNow: { Task { await model.refreshNow() } }) }
            .monitorStopDialogs(stopFlow) { Task { await model.refresh(force: true) } }
            .screenActions(refresh: { Task { await model.refreshNow() } },
                           find: { searchFocused = true },
                           isActive: navigator.path.isEmpty)
            .onChange(of: sortOrder) { applySortOrder() }
            // a link opened while Monitor is already showing
            .onChange(of: navigator.pendingIntent) { Task { await applyPendingLink() } }
            .task(id: "\(model.lens.rawValue)-\(refreshSeconds)") { await refreshLoop() }
    }

    /// The table exists from the start: until the first reading it shows a progress indicator in place of
    /// the rows, and when the scope or the search leaves none it says so there.
    @ViewBuilder private var content: some View {
        switch model.lens {
        case .memory:
            MonitorOutline(rows: visibleRows, sortOrder: $sortOrder, selection: $selection,
                           expanded: model.expansion.binding, icons: model.icons,
                           isLoading: !model.isLoaded(.memory), empty: AnyView(emptyState),
                           rowFor: { model.row($0) }, begin: stopFlow.begin, open: showDetails) { row in
                rowMenu(row)
            }
        case .energy: model.isLoaded(.energy) ? AnyView(energyTable) : AnyView(ProgressView("Reading the process table…"))
        case .diskIO: model.isLoaded(.diskIO) ? AnyView(diskIOTable) : AnyView(ProgressView("Reading the process table…"))
        }
    }

    /// The screen's subtitle: the whole machine, or what the scope narrows to.
    private var subtitle: String {
        guard model.lens == .memory, let category = scope.category, model.hasLoaded else { return model.subtitle }
        let shown = model.rows.filter { $0.category == category }
        let bytes = shown.reduce(Int64(0)) { $0 + $1.memoryBytes }
        let count = shown.reduce(0) { $0 + $1.processCount }
        return "\(category.title) — \(count.formatted()) processes · \(MemorySize.text(bytes))"
    }

    // MARK: - links

    /// A deep link's request, applied once the rows it refers to exist.
    func applyPendingLink() async {
        guard let payload = navigator.takeIntent(for: MemoryGroup.monitor) else { return }
        let link = MonitorLink(payload: payload)
        switch link.lens {
        case "energy": model.lens = .energy
        case "disk": model.lens = .diskIO
        default: break
        }
        if let name = link.scope {
            scope = name == "macos" ? .system : (Scope(rawValue: name) ?? .everything)
        }
        if let query = link.query { search = query }
        if link.inspector { inspectorShown = true }
        for _ in 0..<60 where !model.isLoaded(model.lens) { try? await Task.sleep(for: .milliseconds(100)) }
        if link.expandAll { model.expandEverything() }
        if let name = link.open,
           let row = model.rows.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            model.open([row.id] + row.children.map(\.id))
        }
        if let pid = link.pid {
            scope = .everything
            search = ""
            if let path = MonitorTree.path(toPID: pid, in: model.rows) {
                model.open(path.dropLast())
                selection = path.last
            }
            // the reason is shown whether or not the row is still there
            if let why = link.why { stopFlow.notice = why.sentence }
        }
        // A link only ever SELECTS a row, and only by its exact name: a stop is
        // something a person confirms in the dialog, never something a link starts.
        if let name = link.select ?? link.stop,
           let row = model.rows.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            selection = row.id
        }
    }

    // MARK: - refreshing

    private func refreshLoop() async {
        await model.refresh()
        await applyPendingLink()
        guard refreshSeconds > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double(refreshSeconds)))
            if Task.isCancelled { break }
            await model.refresh()
        }
    }

    /// A click on a column header is the person choosing an order.
    private func applySortOrder() {
        guard let first = sortOrder.first else { return }
        let ascending = first.order == .forward
        let key: MonitorTree.SortKey
        switch first.keyPath {
        case \MonitorRow.name: key = .name
        case \MonitorRow.cpuSort: key = .cpu
        case \MonitorRow.pidSort: key = .pid
        default: key = .memory
        }
        model.setSort(MonitorTree.Sort(key, ascending: ascending))
    }

    // MARK: - the row's menu and the empty state

    @ViewBuilder private func rowMenu(_ row: MonitorRow) -> some View {
        if row.pid != nil || row.iconPID != nil {
            Button(Names.Monitor.showDetails) { showDetails(row) }
        }
        if row.isEnded {
            Button("This process has ended") {}.disabled(true)
        } else if let verb = row.stopVerb {
            Button("\(verb) \(row.name)…") { stopFlow.begin(row.stop) }
        } else if let reason = row.lockedReason {
            Button(reason) {}.disabled(true)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.hasLoaded, visibleRows.isEmpty {
            if search.isEmpty {
                ContentUnavailableView(Names.Monitor.nothingInScope, systemImage: "memorychip",
                                       description: Text("Choose another scope to see more of what is running."))
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    // MARK: - opening

    func showDetails(_ row: MonitorRow) {
        guard let pid = row.pid ?? row.iconPID else { return }
        navigator.push(.memory(.dossier(DossierRoute(name: row.name, pid: pid))))
    }
}
