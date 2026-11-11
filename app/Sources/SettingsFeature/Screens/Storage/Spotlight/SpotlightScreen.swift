import AnalyzersKit
import AppKit
import SwiftUI
import UIComponents

/// Spotlight: which developer folders (node_modules, build output, caches) Spotlight indexes,
/// by project, and whether each is fenced. A fence is one empty file in the folder, placed or
/// lifted on a row or on a selection, and always reversible. Fence All goes through the audit
/// that was just run, like every other cleanup.
struct SpotlightScreen: View {
    @State private var model = StorageReviewModel()
    @State private var review: SpotlightReview?
    @State private var changed: [String: FenceState] = [:]
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\SpotlightNode.sortBytes, order: .reverse)]
    @State private var expansion = RememberedExpansion<String>(screen: "spotlight")
    @State private var problem: String?
    @State private var confirmingAll = false
    @State private var query = ""
    @State private var fencing: Job?
    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator

    private static let parse: @Sendable (WholeRun.Block) -> StorageRows = { block in
        SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: block.banner, lines: block.lines)).rows
    }

    private var tree: [SpotlightNode] {
        let all = SpotlightNode.tree(review?.folders ?? [], changed: changed)
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all.sorted(using: sortOrder) }
        return all.compactMap { project -> SpotlightNode? in
            let hits = (project.children ?? []).filter {
                $0.title.localizedCaseInsensitiveContains(needle) || $0.detail.localizedCaseInsensitiveContains(needle)
                    || project.title.localizedCaseInsensitiveContains(needle)
            }
            guard !hits.isEmpty else { return nil }
            var kept = project
            kept.children = hits
            return kept
        }.sorted(using: sortOrder)
    }

    private var subtitle: String {
        switch model.phase {
        case .ready, .lastKnown:
            guard let review else { return "" }
            let open = review.folders.filter { (changed[$0.path] ?? $0.state) == .notFenced }.count
            return "\(review.folders.count) folders · \(open) not fenced"
        case .running: return model.job?.step ?? "Checking…"
        default: return ""
        }
    }

    var body: some View {
        DataScreen(title: Names.Screen.spotlight, subtitle: subtitle) {
            StoragePhaseContent(model: model, emptyTitle: "No Check Yet",
                                emptyText: "Looks at which of your project folders Spotlight is indexing. Nothing changes until you fence a folder.",
                                preview: preview) { table }
        }
        .searchable(text: $query, prompt: "Search")
        .toolbar { actions }
        .onAppear { model.adopt(store, kind: .spotlight) }
        .task(id: JobStamp(model.job)) {
            model.refreshPhase()
            await model.load(kind: .spotlight, parse: Self.parse, reviewRow: { $0.reviewRow })
            await model.loadLastKnown(kind: .spotlight, parse: Self.parse, reviewRow: { $0.reviewRow })
        }
        .task(id: model.block?.offset) {
            guard let block = model.block else { review = nil; return }
            review = await Task.detached {
                SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: block.banner, lines: block.lines))
            }.value
            changed = [:]
        }
        // Fence All ran through the check: once it is done, read the fences as they are now
        .task(id: JobStamp(fencing)) {
            guard let fencing, case .succeeded = fencing.state, let review else { return }
            for folder in review.folders where FenceMarker.isFenced(folder.path) { changed[folder.path] = .fenced }
            self.fencing = nil
        }
        .confirmationDialog("Fence Every Unfenced Folder?", isPresented: $confirmingAll, titleVisibility: .visible) {
            Button("Fence All", role: .destructive) { fenceAll() }
        } message: {
            Text("Places an empty .metadata_never_index file in every unfenced developer folder the check found, so Spotlight stops indexing them. Nothing is moved or deleted, and each fence can be lifted here or by deleting that file.")
        }
        .alert("Fence Not Changed", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    // MARK: - the table

    @ViewBuilder private var table: some View {
        VStack(spacing: 0) {
            if let review {
                Label("\(review.status) \(review.verdictSentence)", systemImage: "magnifyingglass")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
            }
            if tree.isEmpty {
                ContentUnavailableView("No Developer Folders", systemImage: "checkmark.circle",
                                       description: Text("The check found no node_modules, build output or caches under your projects."))
            } else {
                OutlineTable(tree, children: \.children, selection: $selection, sortOrder: $sortOrder,
                             expanded: expansion.binding, autosave: "spotlight") {
                    OutlineColumn("name", Names.Column.name, sortUsing: KeyPathComparator(\SpotlightNode.sortName)) { node in
                        Label {
                            VStack(alignment: .leading) {
                                Text(node.title).lineLimit(1)
                                Text(node.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        } icon: { Image(systemName: node.isGroup ? "folder" : "folder.badge.gearshape") }
                    }
                    .help { $0.detail }
                    .lines { _ in 2 }
                    .typeSelect { $0.title }
                    OutlineColumn("size", Names.Column.size, text: { $0.bytes.map(ByteSize.format) ?? "" },
                                  sortUsing: KeyPathComparator(\SpotlightNode.sortBytes))
                        .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                        .width(min: 72, ideal: 96, max: 140)
                    OutlineColumn("fenced", Names.Column.fenced, sortUsing: KeyPathComparator(\SpotlightNode.sortState)) { node in
                        if let state = node.state, let path = node.path {
                            Toggle(state.title, isOn: Binding(get: { state == .fenced }, set: { set([path], fenced: $0) }))
                                .toggleStyle(.checkbox)
                                .help(state == .fenced ? "Lift the fence so Spotlight indexes this folder again"
                                                       : "Fence this folder so Spotlight stops indexing it")
                        }
                    }
                    .width(min: 96, ideal: 112, max: 160)
                }
                .contextMenu({ ids in menu(for: ids) }, primaryAction: nil)
            }
        }
    }

    @ViewBuilder private func menu(for ids: Set<String>) -> some View {
        let targets = SpotlightNode.folders(under: ids, in: tree)
        if targets.contains(where: { $0.state == .notFenced }) {
            Button("Fence") { set(targets.filter { $0.state == .notFenced }.compactMap(\.path), fenced: true) }
        }
        if targets.contains(where: { $0.state == .fenced }) {
            Button("Unfence") { set(targets.filter { $0.state == .fenced }.compactMap(\.path), fenced: false) }
        }
        if let first = targets.first?.path {
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(targets.compactMap(\.path).joined(separator: "\n"), forType: .string)
            }
        }
    }

    // MARK: - actions

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItem {
            if model.phase == .running {
                Button { model.job?.cancel() } label: { Label(Names.Review.stop, systemImage: "stop.fill") }
            } else {
                Button { preview() } label: { Label(Names.Review.preview, systemImage: "eye") }
                    .help("Check which folders Spotlight indexes; nothing is changed")
            }
        }
        .toolbarRank(.primary)
        ToolbarItem {
            let targets = SpotlightNode.folders(under: selection, in: tree)
            Button { set(targets.filter { $0.state == .notFenced }.compactMap(\.path), fenced: true) } label: {
                Label("Fence", systemImage: "lock")
            }
            .disabled(!targets.contains { $0.state == .notFenced })
            .help("Fence the selected folders")
        }
        .toolbarRank(.primary)
        ToolbarItem {
            let targets = SpotlightNode.folders(under: selection, in: tree)
            Button { set(targets.filter { $0.state == .fenced }.compactMap(\.path), fenced: false) } label: {
                Label("Unfence", systemImage: "lock.open")
            }
            .disabled(!targets.contains { $0.state == .fenced })
            .help("Lift the fence from the selected folders")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            Button { confirmingAll = true } label: { Label("Fence All", systemImage: "lock.shield") }
                .disabled(!canFenceAll)
                .help("Fence every unfenced folder from the check you just ran")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            Button { navigator.push(.storage(.history(JobKind.spotlight.rawValue))) } label: {
                Label(Names.Review.history, systemImage: "clock.arrow.circlepath")
            }
            .help("Every time this ran, and what it did")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            if let log = JobKind.spotlight.log {
                Button { navigator.push(.overview(.raw(.log(log.rawValue)))) } label: {
                    Label(Names.Review.showRawOutput, systemImage: "doc.plaintext")
                }
            }
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            if let command = review?.rebuildCommand {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: { Label("Copy Rebuild Command", systemImage: "doc.on.doc") }
                .help("Copy the Terminal command that rebuilds Spotlight's index")
            }
        }
        .toolbarRank(.secondary)
    }

    /// A check that finished well, recent enough to apply, and that found something unfenced.
    private var canFenceAll: Bool {
        guard model.phase == .ready, let job = model.job, case .succeeded = job.state else { return false }
        return (review?.folders ?? []).contains { (changed[$0.path] ?? $0.state) == .notFenced }
    }

    private func preview() { model.startPreview(store, kind: .spotlight, options: JobOptions()) }

    /// The app's own small action on single folders: an empty file, placed or lifted.
    private func set(_ paths: [String], fenced: Bool) {
        var failures: [String] = []
        for path in paths {
            do {
                if fenced { try FenceMarker.fence(path) } else { try FenceMarker.unfence(path) }
                changed[path] = fenced ? .fenced : .notFenced
            } catch { failures.append("\(error)") }
        }
        if !failures.isEmpty { problem = failures.prefix(3).joined(separator: "\n") }
    }

    private func fenceAll() {
        guard let job = model.job else { return }
        let apply = store.apply(from: job, approved: .everything)
        if case .failed(let failure) = apply.state { problem = failure.message } else { fencing = apply }
    }
}
