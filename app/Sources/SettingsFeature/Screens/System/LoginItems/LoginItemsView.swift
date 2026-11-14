import AnalyzersKit
import SwiftUI
import UIComponents

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
/// The category tabs are the shared bar under the toolbar (`scopeTabsToolbar`). Toolbar, in the
/// order it gives up space: Audit stays; the filter, Past Runs, Remove Leftovers and Stop are
/// `.toolbarRank(.secondary)` and move into the system's overflow first; search folds to its
/// icon; the inspector toggle is automatic.
struct LoginItemsView: View {

    /// The tabs: the kinds the audit distinguishes (apps that open at login,
    /// background programs, leftovers from apps that are gone) and the history
    /// of what was added.
    enum Tab: String, Hashable, Identifiable, CaseIterable, Sendable {
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
    /// Which groups are open, kept across window close and relaunch; a few groups start open.
    @State private var expansion = RememberedExpansion<String>(screen: "loginItems")
    @State private var changeSelection: StartupChange.ID?
    @State private var showInspector = false
    @State private var confirmRemoval = false
    /// What the open confirmation names and what Remove sends, fixed when it opened: a later
    /// audit changes the table, never the dialog (the dialog closes instead, and says why).
    @State private var frozen: FrozenRemoval?
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

    private var tabItems: [ScopeTabItem<Tab>] {
        Tab.allCases.map { ScopeTabItem(value: $0, title: $0.title, symbol: $0.symbol, count: count($0)) }
    }

    var body: some View {
        DataScreen(title: Names.Screen.loginItems, subtitle: subtitle) { content }
            .scopeTabsToolbar(screen: "loginItems", items: tabItems, selection: $tab)
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
                    guard let frozen else { return }
                    if !model.remove(frozen.scope, approved: frozen.approval, in: store) { auditFirst = true }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(removalMessage)
            }
            .alert("Audit Again First", isPresented: $auditFirst) {
                Button("Audit") { model.startAudit(in: store) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The list changed, or is not from the audit a removal would be built from, so nothing was removed. Audit again, then remove.")
            }
            // an audit that finishes under an open confirmation: close it and say why
            .onChange(of: model.inventory?.stamp) {
                guard confirmRemoval else { return }
                confirmRemoval = false
                frozen = nil
                auditFirst = true
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
            // a few groups start open, many start closed; never once a person chose
            .onChange(of: groups.map(\.id), initial: true) {
                expansion.seedIfUntouched(groups.count <= 6 ? Set(groups.filter { $0.count > 1 }.map(\.id)) : [])
            }
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
                if model.isBusy {
                    LoadingState("Checking Startup Items", detail: "Looking at login items, launch agents and helper tools.")
                } else {
                    EmptyState {
                        Label("No Audit Yet", systemImage: "person.crop.circle.badge.questionmark")
                    } description: {
                        Text(model.permission.sentence ?? "Run the audit to see everything that starts by itself.")
                    }
                }
            } else if groups.isEmpty {
                if let unread = unreadableSentence {
                    EmptyState("Login Items Not Read", systemImage: "exclamationmark.triangle", description: Text(unread))
                } else {
                    EmptyState(emptyTitle, systemImage: tab.symbol, description: Text(emptyDescription))
                }
            } else {
                StartupItemTable(groups: groups, autosave: "loginItems.\(tab.rawValue)", selection: $selection,
                                 expansion: expansion,
                                 onShowInFinder: reveal, onRemove: askToRemove)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // what the tab holds, and when it was last audited: a sentence of its own
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tabNote)
                                if let sentence = auditSentence { Text(sentence) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding()
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let note = model.failure ?? model.permission.sentence ?? unreadableSentence {
                            Label(note, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).padding()
                        }
                    }
            }
        }
    }

    /// The Apps tab lists the System Settings login items; when the last audit could not read them, it says so.
    private var unreadableSentence: String? {
        tab == .apps && model.inventory?.loginItemsUnreadable == true ? StartupInventory.loginItemsUnreadableSentence : nil
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
            Button { model.startAudit(in: store) } label: {
                Label("Audit", systemImage: "checklist")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.isBusy)
            .help(auditHelp)
        }
        .toolbarRank(.primary)

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
        .toolbarRank(.secondary)

        ToolbarItem(placement: .primaryAction) {
            Button { model.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                .labelStyle(.titleAndIcon)
                .disabled(!model.isBusy)
                .help("Stop the audit")
        }
        .toolbarRank(.secondary)

        ToolbarItem(placement: .primaryAction) {
            Button { navigator.open(target: "activity:find:\(Names.job(.loginItems))") } label: {
                Label("Past Runs", systemImage: "clock.arrow.circlepath")
            }
            .labelStyle(.titleAndIcon)
            .help("See every earlier audit in Activity")
        }
        .toolbarRank(.secondary)

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
        .toolbarRank(.secondary)
        }
    }

    // MARK: - words

    /// One short fact: what the tab is (the counts are on the tabs). When the
    /// audit ran has room for a sentence at the foot of the list and in Audit's tooltip.
    private var subtitle: String {
        if model.inventory == nil, tab != .changes { return model.isBusy ? "Checking…" : "Not audited yet" }
        switch tab {
        case .apps: return "Open when you log in"
        case .background: return "Working for apps in the background"
        case .leftovers: return "From apps that are gone"
        case .changes: return "Added to startup, newest first"
        }
    }

    /// "Audited 3 minutes ago, 29 items."
    private var auditSentence: String? {
        guard let inventory = model.inventory else { return nil }
        let when = inventory.ranAt.map { $0.formatted(.relative(presentation: .named)) } ?? "earlier"
        return "Audited \(when): \(inventory.items.count) items, \(inventory.leftovers.count) of them leftovers."
    }

    private var auditHelp: String {
        "Look at everything that starts by itself, changing nothing." + (auditSentence.map { " " + $0 } ?? "")
    }

    private var removeHelp: String {
        if model.removable.isEmpty { return "No leftover can be removed from here" }
        if !model.canRemove(in: store) { return "Audit again first: this list is not from a recent audit" }
        return "Remove the leftovers the audit found in your own folders"
    }

    private var removalTitle: String {
        let count = frozen?.scope.count ?? 0
        return count == 1 ? "Remove this leftover?" : "Remove \(count) leftovers?"
    }

    /// What each tab holds, in a sentence (the table can be two rows in a tall window).
    private var tabNote: String {
        switch tab {
        case .apps: "Apps set to open when you log in: the same list as System Settings › Login Items."
        case .background: "Programs that start by themselves in the background, under the app or developer they belong to."
        case .leftovers: "Items whose app is gone. The ones in your own folders can be removed here; for the others a command is shown to copy."
        case .changes: "What was added to startup."
        }
    }

    private var removalMessage: String {
        let names = frozen?.scope.map(\.name) ?? []
        let sentence = names.count == 1
            ? "The program it starts is gone, so nothing depends on it. This cannot be undone."
            : "The program each one starts is gone, so nothing depends on them. This cannot be undone."
        let full = names.count > 3 ? " " + ReviewWording.fullNames(names) + "." : ""
        return "\(ReviewWording.nameList(names)). \(sentence)\(full)"
    }

    // MARK: - actions

    private func reveal(_ item: StartupItem) {
        guard let path = item.revealPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Remove from a row or the inspector: just that leftover when the script
    /// can narrow to it (it can), otherwise every leftover.
    private func askToRemove(_ item: StartupItem) {
        present(StartupRemoval.scope(chosen: [item], removable: model.removable))
    }

    private func askToRemoveAll() {
        present(StartupRemoval.scopeAll(removable: model.removable))
    }

    /// Ask to confirm, with what is sent frozen now, or say why not: a removal without
    /// an audit behind this very list would act on something else than the dialog shows.
    private func present(_ scope: [StartupItem]) {
        guard !scope.isEmpty else { return }
        guard model.canRemove(in: store) else { auditFirst = true; return }
        frozen = FrozenRemoval(scope: scope,
                               approval: StartupRemoval.approval(for: scope, removable: model.removable))
        confirmRemoval = true
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
                let open = expansion.binding   // a person's choice: it ends the seeding
                open.wrappedValue.insert("\(parts[0])|\(parts[1])")
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

/// A removal as the confirmation shows it: the items named and the approval that will be sent.
private struct FrozenRemoval {
    let scope: [StartupItem]
    let approval: ApprovedSet
}
