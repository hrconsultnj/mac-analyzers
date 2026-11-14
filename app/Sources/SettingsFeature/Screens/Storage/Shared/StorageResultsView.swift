import AnalyzersKit
import SwiftUI
import UIComponents

/// A finished run's results, in the same tabs and groups as the task's own screen (the run
/// screen's results slot): read from the run's own block of the log, whole, with what
/// happened to each row where the run acted. Nothing here can apply anything.
struct StorageResultsView<Category: StorageCategory>: View {
    let row: ActivityRow
    let kind: JobKind
    /// Builds the rows from the run's block; `results` is true for a run that acted.
    let parse: @Sendable (WholeRun.Block, _ results: Bool) -> StorageRows
    let screenKey: String

    @State private var loaded: Loaded?
    @State private var finished = false
    @State private var category: StorageTab
    @Environment(JobStore.self) private var store

    private struct Loaded {
        let rows: StorageRows
        let session: ReviewSession
        let acted: Bool
    }

    init(row: ActivityRow, kind: JobKind, screenKey: String,
         parse: @escaping @Sendable (WholeRun.Block, Bool) -> StorageRows) {
        self.row = row
        self.kind = kind
        self.screenKey = screenKey
        self.parse = parse
        let first = Category.allCases.first
        _category = State(initialValue: StorageTab(id: first?.rawValue ?? "", title: first?.title ?? "", symbol: first?.symbol ?? "folder"))
    }

    private var filled: [StorageTab] { loaded?.rows.tabs(Category.self) ?? [] }
    private var current: StorageTab { filled.first { $0 == category } ?? filled.first ?? category }

    var body: some View {
        content
            .modifier(StorageResultTabs(screen: screenKey, items: tabItems, selection: Binding(get: { current }, set: { category = $0 })))
            .task(id: row.id) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let loaded {
            if loaded.rows.rows.isEmpty {
                EmptyState("Nothing Was Found", systemImage: "checkmark.circle",
                           description: Text("This run found nothing to list."))
            } else {
                ReviewTable(session: loaded.session, readOnly: true,
                            note: loaded.acted ? nil : "This was a preview: nothing was changed.",
                            only: Set(loaded.rows.rows(inTab: current.rawValue).map(\.id)), screen: "run.\(screenKey)")
            }
        } else if finished {
            EmptyState("Details Weren't Kept", systemImage: "text.alignleft",
                       description: Text("Show Raw Output has the text this run left."))
        } else {
            LoadingState()
        }
    }

    private var tabItems: [ScopeTabItem<StorageTab>] {
        guard let rows = loaded?.rows else { return [] }
        return filled.map { ScopeTabItem(value: $0, title: $0.title, symbol: $0.symbol, count: rows.count(inTab: $0.rawValue)) }
    }

    private func load() async {
        guard let banner = row.header.map({ $0.components(separatedBy: " · ").first ?? $0 }) else {
            finished = true
            return
        }
        let began = row.started
        let parse = parse
        let kind = kind
        let found = await Task.detached(priority: .userInitiated) { () -> (StorageRows, Bool)? in
            guard let block = StorageLog.block(banner: banner, of: kind, notBefore: began) else { return nil }
            let acted = block.banner.contains("APPLY")
            return (parse(block, acted), acted)
        }.value
        finished = true
        guard let (rows, acted) = found else { return }
        loaded = Loaded(rows: rows, session: ReviewSession(readOnly: rows.rows.map(\.reviewRow)), acted: acted)
    }
}

private struct StorageResultTabs: ViewModifier {
    let screen: String
    let items: [ScopeTabItem<StorageTab>]
    @Binding var selection: StorageTab

    @ViewBuilder func body(content: Content) -> some View {
        if (2...6).contains(items.count) {
            content.scopeTabsToolbar(screen: "run.\(screen)", items: items, selection: $selection)
        } else {
            content
        }
    }
}
