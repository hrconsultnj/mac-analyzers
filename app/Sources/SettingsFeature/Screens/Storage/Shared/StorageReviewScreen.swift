import AnalyzersKit
import SwiftUI
import UIComponents

/// A Storage cleanup's own screen: Preview in the toolbar, the preview's rows as tabs (the
/// kinds of thing), groups (the project, app or agent they belong to) and ticks in the shared
/// review table, one Apply that goes through `JobStore.apply(from:approved:)` and nothing
/// else, and the task's History one tap away. Caches & Builds, Downloads and Temp & Agents are
/// this view with their own words and their own row builder.
///
/// What it shows depends on where the preview is: nothing yet (and the newest preview in the
/// log, read-only, when there is one), running with Stop, failed, stopped, reading the results,
/// results that cannot be shown, or the review itself. The toolbar is the same in every state
/// except that Preview becomes Stop while it runs.
struct StorageReviewScreen<Category: StorageCategory>: View {
    let model: StorageReviewModel
    let title: String
    let kind: JobKind
    /// Remembers this screen's tab and open groups.
    let screenKey: String
    let options: JobOptions
    let parse: @Sendable (WholeRun.Block) -> StorageRows
    /// Whether the log's newest preview is of what the screen is set to (Daily/Deep, Trash/permanent).
    let lastKnownMatches: @Sendable (WholeRun.Block) -> Bool
    let applyTitle: String
    let confirmation: ReviewConfirmation
    /// What the empty screen says.
    let emptyText: String
    var emptyTitle = "No Preview Yet"
    /// What the subtitle starts with when there is a review (the mode: "Deep").
    var subtitlePrefix: String?

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var category: Category
    @State private var query = ""

    init(model: StorageReviewModel, title: String, kind: JobKind, screenKey: String, options: JobOptions,
         parse: @escaping @Sendable (WholeRun.Block) -> StorageRows,
         lastKnownMatches: @escaping @Sendable (WholeRun.Block) -> Bool = { _ in true }, applyTitle: String,
         confirmation: ReviewConfirmation, emptyText: String, emptyTitle: String = "No Preview Yet",
         subtitlePrefix: String? = nil) {
        self.model = model
        self.title = title
        self.kind = kind
        self.screenKey = screenKey
        self.options = options
        self.parse = parse
        self.lastKnownMatches = lastKnownMatches
        self.applyTitle = applyTitle
        self.confirmation = confirmation
        self.emptyText = emptyText
        self.emptyTitle = emptyTitle
        self.subtitlePrefix = subtitlePrefix
        _category = State(initialValue: Category.allCases.first!)
    }

    private var filled: [Category] { model.rows?.filled(Category.self) ?? [] }
    private var current: Category { filled.contains(category) ? category : (filled.first ?? category) }

    private var subtitle: String {
        switch model.phase {
        case .empty: return ""
        case .running: return model.job?.step ?? "Previewing…"
        case .failed, .stopped, .unreadable: return ""
        case .loading: return "Reading the results…"
        case .ready:
            return ([subtitlePrefix, model.session?.summary] + (model.rows?.facts ?? [])).compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .lastKnown:
            return model.asOf.flatMap(StorageLog.ago).map { "From the preview \($0)" } ?? "From the last preview"
        }
    }

    var body: some View {
        DataScreen(title: title, subtitle: subtitle) { content }
            .searchable(text: $query, prompt: "Search")
            .toolbar { actions }
            .modifier(StorageTabs(screen: screenKey, items: tabItems, selection: tabBinding))
            .onAppear { model.adopt(store, kind: kind) }
            .task(id: LoadKey(stamp: JobStamp(model.job), options: options)) {
                model.refreshPhase()
                await model.load(kind: kind, parse: parse, reviewRow: { $0.reviewRow })
                await model.loadLastKnown(kind: kind, matches: lastKnownMatches, parse: parse, reviewRow: { $0.reviewRow })
            }
    }

    // MARK: - content

    private var content: some View {
        StoragePhaseContent(model: model, emptyTitle: emptyTitle, emptyText: emptyText, preview: startPreview) { review }
    }

    @ViewBuilder private var review: some View {
        if let rows = model.rows, let session = model.session {
            if rows.rows.isEmpty {
                ContentUnavailableView("Nothing to Clean", systemImage: "checkmark.circle",
                                       description: Text("This preview found nothing to remove."))
            } else {
                ReviewTable(session: session, preview: model.phase == .lastKnown ? nil : model.job,
                            applyTitle: applyTitle, confirmation: confirmation, readOnly: model.phase == .lastKnown,
                            note: model.phase == .lastKnown ? "Preview again to review these and apply." : nil,
                            onPreviewAgain: { startPreview() }, onApplied: { _ in },
                            only: shownIDs(rows), tabs: filled.map { Set(rows.rows(in: $0).map(\.id)) },
                            screen: screenKey)
                    .safeAreaInset(edge: .top, spacing: 0) { notesStrip }
            }
        }
    }

    @ViewBuilder private var notesStrip: some View {
        if let notes = model.rows?.notes, !notes.isEmpty {
            VStack(alignment: .leading) {
                ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.bar)
        }
    }

    /// What the table shows: the tab's rows, or every row that matches a search.
    private func shownIDs(_ rows: StorageRows) -> Set<String> {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Set(rows.rows(in: current).map(\.id)) }
        return Set(rows.rows.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || ($0.detail?.localizedCaseInsensitiveContains(needle) ?? false)
        }.map(\.id))
    }

    // MARK: - toolbar and tabs

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItem {
            if model.phase == .running {
                Button { model.job?.cancel() } label: { Label(Names.Review.stop, systemImage: "stop.fill") }
            } else {
                Button { startPreview() } label: { Label(Names.Review.preview, systemImage: "eye") }
                    .help("Look at what a cleanup would do; nothing is changed")
            }
        }
        .toolbarRank(.primary)
        ToolbarItem {
            Button { navigator.push(.storage(.history(kind.rawValue))) } label: {
                Label(Names.Review.history, systemImage: "clock.arrow.circlepath")
            }
            .help("Every time this ran, and what it did")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            if let log = kind.log {
                Button { navigator.push(.overview(.raw(.log(log.rawValue)))) } label: {
                    Label(Names.Review.showRawOutput, systemImage: "doc.plaintext")
                }
                .help("The cleanup's own log, in the app")
            }
        }
        .toolbarRank(.secondary)
    }

    private var tabItems: [ScopeTabItem<Category>] {
        guard let rows = model.rows else { return [] }
        return filled.map { ScopeTabItem(value: $0, title: $0.title, symbol: $0.symbol, count: rows.count(in: $0)) }
    }

    private var tabBinding: Binding<Category> { Binding(get: { current }, set: { category = $0 }) }

    private func startPreview() { model.startPreview(store, kind: kind, options: options) }
}

/// What reloads a screen: its preview moving on, or its settings (Daily/Deep, Trash/permanent) changing.
private struct LoadKey: Equatable {
    let stamp: JobStamp
    let options: JobOptions
}

/// The tabs in the toolbar when there are two or more; a screen with one kind of thing has none.
private struct StorageTabs<Category: StorageCategory>: ViewModifier {
    let screen: String
    let items: [ScopeTabItem<Category>]
    @Binding var selection: Category

    @ViewBuilder func body(content: Content) -> some View {
        if (2...6).contains(items.count) {
            content.scopeTabsToolbar(screen: screen, items: items, selection: $selection)
        } else {
            content
        }
    }
}

/// What a Storage screen shows for where its preview is: nothing yet, running with Stop, failed,
/// stopped, reading the results, results that cannot be shown, or — when there are results —
/// whatever the screen draws for them. The same words on every Storage screen.
struct StoragePhaseContent<Ready: View>: View {
    let model: StorageReviewModel
    var emptyTitle = "No Preview Yet"
    let emptyText: String
    let preview: () -> Void
    @ViewBuilder let ready: () -> Ready

    var body: some View {
        switch model.phase {
        case .empty:
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "eye")
            } description: {
                Text(emptyText)
            } actions: {
                Button(Names.Review.preview, action: preview).buttonStyle(.borderedProminent)
            }
        case .running:
            VStack {
                ProgressView()
                Text(model.job?.step ?? "Previewing…").foregroundStyle(.secondary)
                Button(Names.Review.stop, role: .cancel) { model.job?.cancel() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            retry("Preview Failed", systemImage: "exclamationmark.triangle", text: message)
        case .stopped:
            retry("Preview Stopped", systemImage: "stop.circle", text: "Nothing was changed.")
        case .unreadable(let why):
            retry("Results Can't Be Shown", systemImage: "questionmark.folder",
                  text: "\(why) Nothing from it can be applied.")
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready, .lastKnown:
            ready()
        }
    }

    private func retry(_ title: String, systemImage: String, text: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(text)
        } actions: {
            Button(Names.Review.previewAgain, action: preview).buttonStyle(.borderedProminent)
        }
    }
}
