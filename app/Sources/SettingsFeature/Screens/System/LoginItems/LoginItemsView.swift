import AnalyzersKit
import SwiftUI

/// Login & Startup Items: everything that starts by itself on this Mac, as a
/// table you can sort and search, with what the audit found about each one.
/// The categories are tabs: Apps that open at login, Background Items working
/// for them, Leftovers from apps that are gone, and the Changes history.
/// Inside a category an app or developer is one row that opens to its items.
///
/// One job per file next to it:
///   LoginItemsModel.swift         the inventory, the history and the audit / removal jobs
///   StartupItemTable.swift        the outline table (StartupNode.swift is its row)
///   StartupItemInspector.swift    the selected item in full, with its actions
///   StartupChangesList.swift      the Changes scope: a day-grouped list
///   StartupItem+Presentation.swift  icon, colour and sort keys
///
/// Toolbar, in the order it gives up space: the category tabs and Audit stay;
/// the filter, Remove Leftovers and Stop move into the system's overflow first;
/// search folds to its icon; the inspector toggle is automatic.
struct LoginItemsView: View {

    /// The tabs: the kinds the audit distinguishes (apps that open at login,
    /// background programs, leftovers from apps that are gone) and the history
    /// of what was added.
    enum Tab: Hashable, Identifiable, CaseIterable {
        case apps, background, leftovers, changes
        var id: Self { self }
        var category: StartupItem.Category? {
            switch self {
            case .apps: .apps
            case .background: .background
            case .leftovers: .leftovers
            case .changes: nil
            }
        }
        var title: String { category?.title ?? Names.Startup.categoryChanges }
        var symbol: String { category?.symbol ?? "clock.arrow.circlepath" }
    }

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var model = LoginItemsModel()
    @State private var tab: Tab = .apps
    @State private var administratorOnly = false
    @State private var notCheckedOnly = false
    @State private var query = ""
    @State private var selection: StartupNode.ID?
    @State private var opened: [StartupGroup.ID: Bool] = [:]
    @State private var changeSelection: StartupChange.ID?
    @State private var showInspector = false
    @State private var confirmRemoval = false
    @State private var removalScope: [StartupItem] = []
    @State private var auditFirst = false

    private var groups: [StartupGroup] {
        guard let category = tab.category, let inventory = model.inventory else { return [] }
        return inventory.groups(in: category, matching: { item in
            (!administratorOnly || item.needsAdministrator) && (!notCheckedOnly || item.finding == .notChecked)
        })
            .compactMap { group in
                guard !query.isEmpty else { return group }
                let kept = group.items.filter { item in
                    [item.name, item.owner, item.label, item.kind.title]
                        .contains { $0.localizedCaseInsensitiveContains(query) }
                }
                return kept.isEmpty ? nil : StartupGroup(category: group.category, name: group.name, items: kept)
            }
    }

    private var selectedItem: StartupItem? { model.items.first { $0.id == selection } }
    private var selectedGroup: StartupGroup? {
        guard let category = tab.category else { return nil }
        return model.inventory?.groups(in: category).first { $0.id == selection }
    }

    var body: some View {
        content
            .navigationTitle(Names.Screen.loginItems)
            .navigationSubtitle(subtitle)
            .searchable(text: $query, prompt: tab == .changes ? "Search changes" : "Search startup items")
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                Group {
                    if let item = selectedItem {
                        StartupItemInspector(item: item,
                                             onShowInFinder: { reveal(item) },
                                             onRemove: { askToRemove(item) })
                    } else if let group = selectedGroup {
                        StartupGroupInspector(group: group)
                    }
                }
                .inspectorColumnWidth(min: 240, ideal: 240, max: 360)
            }
            .confirmationDialog(removalTitle, isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    // the list can have changed under an open confirmation
                    if !model.remove(removalScope, in: store) { auditFirst = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(removalMessage)
            }
            .alert("Audit Again First", isPresented: $auditFirst) {
                Button("Audit") { model.startAudit(in: store) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The list on screen is not from the audit that a removal would be built from, so nothing was removed. Audit again, then remove.")
            }
            .task {
                model.adopt(from: store)
                await model.reload()
                applyPendingLink()
                // Nothing to show yet, or leftovers with no audit behind them to
                // remove from: take a look ourselves (it changes nothing), but only
                // when macOS will not have to ask first. Otherwise the screen says
                // so and waits for Audit.
                await model.checkPermission()
                let needsLook = model.inventory == nil
                    || (!model.removable.isEmpty && !model.canRemove(in: store))
                if needsLook, model.permission == .granted, !model.isBusy { model.startAudit(in: store) }
            }
            .onChange(of: navigator.pendingIntent) { applyPendingLink() }
            .onChange(of: model.audit?.stamp) { _, stamp in
                if stamp?.stage == .succeeded { Task { await model.reload() } }
            }
            .onChange(of: model.removal?.stamp) { _, stamp in
                if stamp?.stage == .succeeded { model.finishRemoval(in: store) }
            }
            .onChange(of: selection) { showInspector = selection != nil }
            .onChange(of: tab) { selection = nil; showInspector = false }
    }

    // MARK: - content

    @ViewBuilder private var content: some View {
        switch tab {
        case .changes:
            StartupChangesList(changes: filteredChanges, inventory: model.inventory,
                               selection: $changeSelection,
                               onShowInItems: showInItems,
                               onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0)]) })
        default:
            if model.inventory == nil {
                ContentUnavailableView {
                    Label(model.isBusy ? "Checking Startup Items" : "No Audit Yet", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text(model.isBusy
                         ? "Looking at login items, launch agents and helper tools."
                         : (model.permission.sentence ?? "Run the audit to see everything that starts by itself."))
                }
            } else if groups.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: tab.symbol, description: Text(emptyDescription))
            } else {
                StartupItemTable(groups: groups, selection: $selection, opened: $opened,
                                 onShowInFinder: reveal, onRemove: askToRemove)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let note = model.failure ?? model.permission.sentence {
                            Label(note, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).padding()
                        }
                    }
            }
        }
    }

    private var filteredChanges: [StartupChange] {
        query.isEmpty ? model.changes : model.changes.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.owner.localizedCaseInsensitiveContains(query)
        }
    }

    private func count(_ tab: Tab) -> Int? {
        guard model.loaded else { return nil }
        switch tab {
        case .changes: return model.changes.count
        default: return tab.category.flatMap { model.inventory?.items(in: $0).count }
        }
    }

    private var emptyTitle: String {
        switch tab {
        case .leftovers: "No Leftovers"
        case .apps: "No Apps"
        default: "No Background Items"
        }
    }

    private var emptyDescription: String {
        if administratorOnly || notCheckedOnly { return "Nothing matches the filter. Turn it off in the Filter menu." }
        switch tab {
        case .leftovers: return "Every login item and background program still has its app."
        case .apps: return "No app is set to open at login."
        default: return "Nothing runs in the background by itself."
        }
    }

    // MARK: - toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScopeButtons(items: Tab.allCases, selection: $tab, title: \.title, symbol: \.symbol,
                         count: count)
        }
        .rank(.high)

        // the tabs show a selection; the actions are a separate group
        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .primaryAction) {
            Button { model.startAudit(in: store) } label: {
                Label("Audit", systemImage: "checklist")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.isBusy)
            .help("Look at everything that starts by itself, changing nothing")
        }
        .rank(.high)

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle(Names.Startup.filterAdministrator, isOn: $administratorOnly)
                Toggle(Names.Startup.filterNotChecked, isOn: $notCheckedOnly)
            } label: {
                Label("Filter", systemImage: administratorOnly || notCheckedOnly
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .labelStyle(.titleAndIcon)
            .disabled(tab == .changes)
            .help("Narrow the list")
        }
        .rank(.low)

        ToolbarItem(placement: .primaryAction) {
            Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                .labelStyle(.titleAndIcon)
                .disabled(!model.isBusy)
                .help("Stop the audit")
        }
        .rank(.low)

        // Remove Leftovers lives on the Leftovers tab, where the leftovers are
        if tab == .leftovers {
            ToolbarItem(placement: .primaryAction) {
                Button { askToRemoveAll() } label: {
                    Label("Remove Leftovers…", systemImage: "trash")
                }
                .labelStyle(.titleAndIcon)
                .disabled(model.removable.isEmpty || !model.canRemove(in: store) || model.isBusy)
                .help(removeHelp)
            }
            .rank(.high)
        }
    }

    // MARK: - words

    private var subtitle: String {
        if tab == .changes {
            return model.changes.isEmpty ? "Nothing added yet" : "\(model.changes.count) recorded"
        }
        guard let inventory = model.inventory else { return model.isBusy ? "Checking…" : "Not audited yet" }
        let leftovers = inventory.leftovers.count
        let when = inventory.ranAt.map { $0.formatted(.relative(presentation: .named)) } ?? "earlier"
        let found = leftovers == 0 ? "no leftovers" : "\(leftovers) \(leftovers == 1 ? "leftover" : "leftovers")"
        return "\(inventory.items.count) items, \(found) · audited \(when)"
    }

    private var removeHelp: String {
        if model.removable.isEmpty { return "No leftover can be removed from here" }
        if !model.canRemove(in: store) { return "Audit again first: this list is not from a recent audit" }
        return "Remove the leftovers the audit found in your own folders"
    }

    private var removalTitle: String {
        removalScope.count == 1 ? "Remove this leftover?" : "Remove \(removalScope.count) leftovers?"
    }

    private var removalMessage: String {
        let names = removalScope.map(\.name).joined(separator: ", ")
        return "\(names). The program each one starts is gone, so nothing depends on them. This cannot be undone."
    }

    // MARK: - actions

    private func reveal(_ item: StartupItem) {
        guard let path = item.revealPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Remove from a row or the inspector: just that leftover when the script
    /// can narrow to it (it can), otherwise every leftover.
    private func askToRemove(_ item: StartupItem) {
        removalScope = StartupRemoval.scope(chosen: [item], removable: model.removable)
        presentRemoval()
    }

    private func askToRemoveAll() {
        removalScope = model.removable
        presentRemoval()
    }

    /// Ask to confirm, or say why not: a removal without an audit behind this
    /// very list would act on something else than the dialog shows.
    private func presentRemoval() {
        guard !removalScope.isEmpty else { return }
        if model.canRemove(in: store) { confirmRemoval = true } else { auditFirst = true }
    }

    private func showInItems(_ item: StartupItem) {
        tab = Tab.allCases.first { $0.category == item.category } ?? .background
        administratorOnly = false
        notCheckedOnly = false
        query = ""
        selection = item.id
    }

    /// A deep link's request: a tab, or an item to open
    /// (`log:persistence` opens Changes).
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: SystemGroup.loginItems) else { return }
        switch payload {
        case "changes": tab = .changes
        case "leftovers": tab = .leftovers
        case "apps": tab = .apps
        case "background": tab = .background
        default: break
        }
        if payload == "admin" { administratorOnly = true; tab = .background }
        if payload == "notchecked" { notCheckedOnly = true; tab = .background }
        if payload.hasPrefix("open:") {
            // open:<tab>:<group> shows that tab with that group opened
            let parts = payload.dropFirst("open:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let target = Tab.allCases.first(where: { $0.category?.rawValue == parts[0] }) {
                tab = target
                opened["\(parts[0])|\(parts[1])"] = true
            }
        }
        if payload.hasPrefix("select:") {
            let name = String(payload.dropFirst("select:".count))
            if let item = model.items.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                showInItems(item)
                showInspector = true
            }
        }
    }
}
