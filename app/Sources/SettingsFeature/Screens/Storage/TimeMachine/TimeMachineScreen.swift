import AnalyzersKit
import AppKit
import SwiftUI
import UIComponents

/// Time Machine: the local snapshots on this Mac, by day, and one action: thin them all, which releases the space
/// they hold (the "I freed 40 GB but the disk did not move" fix). The backups on the Time Machine disk are never
/// touched. Preview looks (`tm-reclaim.sh --dry-run`); "Thin Snapshots…" asks, then applies THAT preview. Thinning
/// needs a one-time permission, which the screen offers to install through the macOS administrator prompt.
struct TimeMachineScreen: View {
    @State private var model = StorageReviewModel()
    @State private var chosenBackup: Bool?
    @State private var allowed = true
    @State private var asking = false
    @State private var applied: Job?
    @State private var problem: String?
    @State private var allowing = false
    @State private var expansion = RememberedExpansion<String>(screen: "timemachine")
    @State private var selection: Set<String> = []
    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?
    /// Whether the example shows the permission as missing.
    var fixtureNeedsPermission = false

    private static let parse: @Sendable (WholeRun.Block) -> StorageRows = { TimeMachineReview.build(lines: $0.lines).rows }

    /// Whether a backup starts after thinning: the preview's own setting once there is one, else the person's pick.
    private var backup: Bool { model.setting(kind: .tmReclaim, chosen: JobOptions(startBackup: chosenBackup ?? true)).startBackup }
    private var words: CleanWords { model.words(kind: .tmReclaim, chosen: JobOptions(startBackup: chosenBackup ?? true)) }
    private var snapshots: Int { model.rows?.rows.filter(\.isChoosable).count ?? 0 }
    private var canThin: Bool { model.phase == .ready && snapshots > 0 && allowed && applied == nil }

    private var backupBinding: Binding<Bool> {
        Binding(get: { backup }, set: { picked in
            if model.pick(JobOptions(startBackup: picked), kind: .tmReclaim, chosen: JobOptions(startBackup: chosenBackup ?? true), store) { chosenBackup = picked }
        })
    }

    private var subtitle: String {
        switch model.phase {
        case .running: model.job?.step ?? "Looking…"
        case .loading: "Reading the results…"
        default: "Backups on your Time Machine disk are never touched"
        }
    }

    var body: some View {
        DataScreen(title: Names.Screen.timeMachine, subtitle: subtitle) {
            StoragePhaseContent(model: model, emptyTitle: "No Preview Yet",
                                emptyText: "Looks at the local snapshots Time Machine keeps on this Mac, which hold space you have freed. Nothing is thinned until you review it.",
                                preview: preview) { content }
        }
        .toolbar { actions }
        .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) { permissionBar }
        .onAppear {
            model.adopt(store, kind: .tmReclaim)
            if let fixture { model.showFixture(fixture); allowed = !fixtureNeedsPermission }
        }
        // sudo is asked, as this person, whether it would run the command: a rule left by an older version, or one
        // for another account, is "not allowed" here (listing runs nothing and asks for no password)
        .task { if fixture == nil { allowed = await TimeMachinePermission.isAllowed() } }
        .task(id: JobStamp(model.job)) {
            model.refreshPhase()
            await model.load(kind: .tmReclaim, parse: Self.parse, reviewRow: { $0.reviewRow })
            await model.loadLastKnown(kind: .tmReclaim, parse: Self.parse, reviewRow: { $0.reviewRow })
        }
        // the thinning ran: say how it went, then look again at what is left
        .task(id: JobStamp(applied)) {
            guard let finished = applied else { return }
            switch finished.state {
            case .succeeded: applied = nil; model.startPreview(store, kind: .tmReclaim, options: JobOptions(startBackup: backup))
            case .failed(let failure): applied = nil; problem = failure.message
            case .cancelled: applied = nil
            default: break
            }
        }
        .confirmationDialog("Thin \(snapshots) Local \(snapshots == 1 ? "Snapshot" : "Snapshots")?", isPresented: $asking, titleVisibility: .visible) {
            Button(words.applyTitle, role: .destructive) { thin() }
        } message: {
            Text(words.message)
        }
        .alert("Snapshots Not Thinned", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    // MARK: - content

    @ViewBuilder private var content: some View {
        let tree = TimeMachineNode.tree(model.rows ?? StorageRows([]))
        if tree.isEmpty {
            ContentUnavailableView(Names.TimeMachine.nothingToThin, systemImage: "checkmark.circle",
                                   description: Text(Names.TimeMachine.nothingToThinDetail))
        } else {
            OutlineTable(tree, children: \.children, selection: $selection, expanded: expansion.binding, autosave: "timemachine") {
                OutlineColumn("name", Names.Column.name) { node in
                    Label {
                        VStack(alignment: .leading) {
                            Text(node.title).lineLimit(1)
                            if let detail = node.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    } icon: { Image(systemName: node.isGroup ? "calendar" : "clock.arrow.circlepath") }
                }
                .lines { $0.detail == nil ? 1 : 2 }
                OutlineColumn("status", "Status", text: { $0.status }).alignment(.trailing).textStyle { _ in .secondary }
                    .width(min: 96, ideal: 112, max: 160)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
    }

    private var footer: some View {
        HStack {
            Text(snapshots == 0 ? "" : "\(snapshots) local \(snapshots == 1 ? "snapshot" : "snapshots")" + (model.rows?.facts.first.map { " · \($0)" } ?? ""))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    /// The permission, when it is missing: what it is for, and the one button that asks for it.
    @ViewBuilder private var permissionBar: some View {
        if !allowed {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(Names.TimeMachine.permissionTitle, systemImage: "lock").font(.callout.weight(.medium))
                    Text(Names.TimeMachine.permissionDetail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Names.TimeMachine.allow) { allow() }.disabled(allowing)
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    // MARK: - toolbar

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItem {
            if model.phase == .running {
                Button { model.job?.cancel() } label: { Label(Names.Review.stop, systemImage: "stop.fill") }
                    .labelStyle(.titleAndIcon)
            } else {
                Button { preview() } label: { Label(Names.Review.preview, systemImage: "eye") }
                    .labelStyle(.titleAndIcon)
                    .help("Look at the local snapshots; nothing is changed")
            }
        }
        .toolbarRank(.primary)
        ToolbarItem {
            Button { asking = true } label: { Label(Names.TimeMachine.thin, systemImage: "clock.arrow.2.circlepath") }
                .labelStyle(.titleAndIcon)
                .disabled(!canThin)
                .help(allowed ? "Thin every local snapshot, after you confirm" : "Allow thinning first")
        }
        .toolbarRank(.primary)
        ToolbarItem {
            Menu {
                Toggle(Names.TimeMachine.startBackup, isOn: backupBinding)
            } label: { Label("Options", systemImage: "slider.horizontal.3") }
                .labelStyle(.titleAndIcon)
                .help("Whether a Time Machine backup starts after the snapshots are thinned")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            if model.phase == .ready {
                Button { model.discard(store) } label: { Label(Names.Review.discard, systemImage: "xmark.circle") }
                    .labelStyle(.titleAndIcon)
                    .help("Throw this look away; nothing is changed")
            }
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            Button { navigator.push(.storage(.history(JobKind.tmReclaim.rawValue))) } label: {
                Label(Names.Review.history, systemImage: "clock.arrow.circlepath")
            }
            .labelStyle(.titleAndIcon)
            .help("Every time this ran, and what it did")
        }
        .toolbarRank(.secondary)
        ToolbarItem {
            if let log = JobKind.tmReclaim.log {
                Button { navigator.push(.overview(.raw(.log(log.rawValue)))) } label: {
                    Label(Names.Review.showRawOutput, systemImage: "doc.plaintext")
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .toolbarRank(.secondary)
    }

    // MARK: - actions

    private func preview() { model.startPreview(store, kind: .tmReclaim, options: JobOptions(startBackup: backup)) }

    /// Applies the preview that is on screen, and no other: the thinning takes no list, so the review is the gate.
    private func thin() {
        guard let job = model.job else { return }
        let run = store.apply(from: job, approved: .everything)
        if case .failed(let failure) = run.state { problem = failure.message } else { applied = run }
    }

    private func allow() {
        allowing = true
        Task {
            let outcome = await TimeMachinePermission.allow(user: NSUserName())
            allowing = false
            allowed = await TimeMachinePermission.isAllowed()
            if case .failed(let why) = outcome { problem = why }
        }
    }
}
