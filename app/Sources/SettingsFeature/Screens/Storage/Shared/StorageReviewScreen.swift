import AnalyzersKit
import AppKit
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
/// A button a screen adds to the shared review: beside Preview in the empty state, or in the toolbar.
struct ReviewAction: Identifiable {
    let id: String
    let title: String
    var systemImage: String?
    var help: String?
    let action: () -> Void
}

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
    /// Where what is cleared goes ("Goes to the Trash", "Deleted Permanently"): first in the
    /// subtitle in every state, so a person never has to open a dialog to find out.
    var destination: String?
    /// Buttons beside Preview when nothing has been previewed yet (Old Recordings: Choose Folders…).
    var emptyActions: [ReviewAction] = []
    /// Buttons the screen adds to the toolbar (Old Recordings: Sources…).
    var toolbarActions: [ReviewAction] = []
    /// Set when there is nothing to preview yet: Preview is off and says why.
    var previewDisabledReason: String?
    var emptySymbol = "eye"

    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @State private var category: StorageTab
    @State private var query = ""

    init(model: StorageReviewModel, title: String, kind: JobKind, screenKey: String, options: JobOptions,
         parse: @escaping @Sendable (WholeRun.Block) -> StorageRows,
         lastKnownMatches: @escaping @Sendable (WholeRun.Block) -> Bool = { _ in true }, applyTitle: String,
         confirmation: ReviewConfirmation, emptyText: String, emptyTitle: String = "No Preview Yet",
         subtitlePrefix: String? = nil, destination: String? = nil, emptyActions: [ReviewAction] = [],
         toolbarActions: [ReviewAction] = [], previewDisabledReason: String? = nil, emptySymbol: String = "eye") {
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
        self.destination = destination
        self.emptyActions = emptyActions
        self.toolbarActions = toolbarActions
        self.previewDisabledReason = previewDisabledReason
        self.emptySymbol = emptySymbol
        let first = Category.allCases.first
        _category = State(initialValue: StorageTab(id: first?.rawValue ?? "", title: first?.title ?? "", symbol: first?.symbol ?? "folder"))
    }

    private var filled: [StorageTab] { model.rows?.tabs(Category.self) ?? [] }
    private var current: StorageTab { filled.first { $0 == category } ?? filled.first ?? category }

    /// One short fact in the toolbar's subtitle, so it is never cut: where what is cleared goes. While a
    /// preview runs, the step it is on.
    private var subtitle: String {
        switch model.phase {
        case .running: return model.job?.step ?? "Previewing…"
        case .loading: return "Reading the results…"
        default: return destination ?? ""
        }
    }

    /// The rest, as a line over the table: which mode, how old the preview is, the disk's free space.
    private var detailLine: String? {
        let text: String
        switch model.phase {
        case .ready:
            text = ([subtitlePrefix] + (model.rows?.facts ?? [])).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .lastKnown:
            text = ([subtitlePrefix] + [model.asOf.flatMap(StorageLog.ago).map { "From the preview \($0)" } ?? "From the last preview"])
                .compactMap { $0 }.joined(separator: " · ")
        default: return nil
        }
        return text.isEmpty ? nil : text
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
        StoragePhaseContent(model: model, emptyTitle: emptyTitle, emptyText: emptyText, preview: startPreview,
                            emptySymbol: emptySymbol, emptyActions: emptyActions,
                            previewDisabledReason: previewDisabledReason) { review }
    }

    @ViewBuilder private var review: some View {
        if let rows = model.rows, let session = model.session {
            if rows.rows.isEmpty {
                EmptyState("Nothing to Clean", systemImage: "checkmark.circle",
                           description: Text("This preview found nothing to remove."))
            } else {
                ReviewTable(session: session, preview: model.phase == .lastKnown ? nil : model.job,
                            applyTitle: applyTitle, confirmation: confirmation, readOnly: model.phase == .lastKnown,
                            note: model.phase == .lastKnown ? "Preview again to review these and apply." : nil,
                            onPreviewAgain: { startPreview() }, onApplied: { _ in },
                            only: shownIDs(rows), tabs: filled.map { Set(rows.rows(inTab: $0.rawValue).map(\.id)) },
                            screen: screenKey, rowMenu: .files)
                    .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) { notesStrip }
            }
        }
    }

    /// What the preview says that is not a row, as the system's own bar over the table.
    @ViewBuilder private var notesStrip: some View {
        let notes = model.rows?.notes(forTab: current.rawValue) ?? []
        if detailLine != nil || !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let detailLine { Text(detailLine).font(.callout).foregroundStyle(.secondary) }
                ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }
            }
            .barMargin()
        }
    }

    /// What the table shows: the tab's rows, or every row that matches a search.
    private func shownIDs(_ rows: StorageRows) -> Set<String> {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Set(rows.rows(inTab: current.rawValue).map(\.id)) }
        return Set(rows.rows.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || ($0.detail?.localizedCaseInsensitiveContains(needle) ?? false)
        }.map(\.id))
    }

    // MARK: - toolbar and tabs

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItem {
            if model.phase == .running {
                Button { model.job?.cancel() } label: { Label(Names.Review.stop, systemImage: "stop.fill") }
                .labelStyle(.titleAndIcon)
            } else {
                Button { startPreview() } label: { Label(Names.Review.preview, systemImage: "eye") }
                .labelStyle(.titleAndIcon)
                    .disabled(previewDisabledReason != nil)
                    .help(previewDisabledReason ?? "Look at what a cleanup would do; nothing is changed")
            }
        }
        .toolbarRank(.primary)
        ToolbarItem {
            if model.phase == .ready {
                Button { model.discard(store) } label: { Label(Names.Review.discard, systemImage: "xmark.circle") }
                .labelStyle(.titleAndIcon)
                    .help("Throw this review away without applying it")
            }
        }
        .toolbarRank(.secondary)
        ForEach(toolbarActions) { item in
            ToolbarItem {
                Button(action: item.action) { Label(item.title, systemImage: item.systemImage ?? "gearshape") }
                    .labelStyle(.titleAndIcon)
                    .help(item.help ?? item.title)
            }
            .toolbarRank(.primary)
        }
        ToolbarItem {
            Button { navigator.push(.storage(.history(kind.rawValue))) } label: {
                Label(Names.Review.history, systemImage: "clock.arrow.circlepath")
            }
            .labelStyle(.titleAndIcon)
            .help("Every time this ran, and what it did")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            if let log = kind.log {
                Button { navigator.push(.overview(.raw(.log(log.rawValue)))) } label: {
                    Label(Names.Review.showRawOutput, systemImage: "doc.plaintext")
                }
                .labelStyle(.titleAndIcon)
                .help("The cleanup's own log, in the app")
            }
        }
        .toolbarRank(.secondary)
    }

    private var tabItems: [ScopeTabItem<StorageTab>] {
        guard let rows = model.rows else { return [] }
        return filled.map { ScopeTabItem(value: $0, title: $0.title, symbol: $0.symbol, count: rows.count(inTab: $0.rawValue)) }
    }

    private var tabBinding: Binding<StorageTab> { Binding(get: { current }, set: { category = $0 }) }

    private func startPreview() { model.startPreview(store, kind: kind, options: options) }
}

/// What reloads a screen: its preview moving on, or its settings (Daily/Deep, Trash/permanent) changing.
private struct LoadKey: Equatable {
    let stamp: JobStamp
    let options: JobOptions
}

/// The tabs in the toolbar when there are two or more; a screen with one kind of thing has none.
private struct StorageTabs: ViewModifier {
    let screen: String
    let items: [ScopeTabItem<StorageTab>]
    @Binding var selection: StorageTab

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
    var emptySymbol = "eye"
    var emptyActions: [ReviewAction] = []
    var previewDisabledReason: String?
    @ViewBuilder let ready: () -> Ready

    var body: some View {
        switch model.phase {
        case .empty:
            EmptyState {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(emptyText)
            } actions: {
                if previewDisabledReason == nil {
                    Button(Names.Review.preview, action: preview).buttonStyle(.borderedProminent)
                } else {
                    Button(Names.Review.preview, action: preview).disabled(true).help(previewDisabledReason ?? "")
                }
                ForEach(emptyActions) { item in
                    // the one way forward is the prominent button: Choose Folders… when Preview has nothing to look at
                    if previewDisabledReason == nil {
                        Button(item.title, action: item.action)
                    } else {
                        Button(item.title, action: item.action).buttonStyle(.borderedProminent)
                    }
                }
            }
        case .running:
            LoadingState(model.job?.step ?? "Previewing…") {
                Button(Names.Review.stop, role: .cancel) { model.job?.cancel() }
            }
        case .failed(let message):
            retry("Preview Failed", systemImage: "exclamationmark.triangle", text: message,
                  diagnostics: StorageDiagnostics.report(job: model.job, message: message))
        case .stopped:
            retry("Preview Stopped", systemImage: "stop.circle", text: "Nothing was changed.")
        case .unreadable(let why):
            retry("Results Can't Be Shown", systemImage: "questionmark.folder",
                  text: "\(why) Nothing from it can be applied.")
        case .loading:
            LoadingState()
        case .ready, .lastKnown:
            ready()
        }
    }

    private func retry(_ title: String, systemImage: String, text: String, diagnostics: String? = nil) -> some View {
        EmptyState {
            Label(title, systemImage: systemImage)
        } description: {
            Text(text)
        } actions: {
            Button(Names.Review.previewAgain, action: preview).buttonStyle(.borderedProminent)
            if let diagnostics {
                Button(Names.Review.copyDiagnostics) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics, forType: .string)
                }
                .help("Copy the failure and the last lines of output, to send to someone who can help")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What "Copy Diagnostics" puts on the clipboard after a failed run: which script, how it was
/// started, what it said, and the last lines it printed.
enum StorageDiagnostics {
    @MainActor static func report(job: Job?, message: String) -> String? {
        guard let job else { return nil }
        let args = (try? job.kind.previewArgs(job.request.options)) ?? []
        return """
        script: \(job.kind.script.path)
        args: \(args.joined(separator: " "))
        message: \(message)

        \(job.lines.suffix(40).joined(separator: "\n"))
        """
    }
}
