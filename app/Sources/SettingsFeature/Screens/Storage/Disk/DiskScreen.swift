import AnalyzersKit
import SwiftUI

/// Disk: where the space is and what each cleanup could give back, with the way into each
/// cleanup. Capacity and runway on top, one row per storage task (how much its last preview
/// found, and how old that figure is) and the iPhone and iPad backups, which are only listed:
/// the app never removes one.
struct DiskScreen: View {
    @State private var usage: DiskUsage?
    @State private var runway: DiskRunway?
    @State private var runwayReason = ""
    @State private var tasks: [StorageTask] = []
    @State private var backups: [IOSBackup] = []
    @State private var loaded = false
    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    /// The worst case, for `SnapshotRunner`; nil in the app.
    var fixture: (usage: DiskUsage, runway: DiskRunway, reason: String, tasks: [StorageTask])?

    private var reclaimable: Int64 { tasks.compactMap(\.reclaimableBytes).reduce(0, +) }

    var body: some View {
        DataScreen(title: Names.Screen.disk,
                   subtitle: usage.map { "\($0.freeText) free of \($0.totalText)" } ?? "") {
            List {
                capacity
                tasksSection
                backupsSection
            }
        }
        .toolbar {
            ToolbarItem {
                Button { checkAll() } label: { Label("Preview All", systemImage: "eye") }
                    .help("Preview every cleanup on this screen, one after another; nothing is changed")
            }
            .toolbarRank(.primary)
        }
        .task { await load() }
    }

    // MARK: - sections

    @ViewBuilder private var capacity: some View {
        if let usage {
            Section("Capacity") {
                VStack(alignment: .leading) {
                    ProgressView(value: usage.usedFraction).tint(usage.isLow ? .red : nil)
                    Text("\(usage.usedText) used of \(usage.totalText)").foregroundStyle(.secondary)
                    if usage.isLow {
                        Label(usage.lowText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(reclaimable > 0
                             ? "The cleanups below could give back \(ByteSize.format(reclaimable)). Open one to review what it would clear."
                             : "Preview the cleanups below to see what could be cleared.")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Free Space", value: usage.freeText)
                LabeledContent("Full In") {
                    Text(runway?.text ?? "No forecast")
                        .foregroundStyle(runway?.isUrgent == true ? .red : .secondary)
                }
                .help(runwayReason)
            }
        }
    }

    private var tasksSection: some View {
        Section {
            ForEach(tasks) { task in
                Button { open(task) } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text(taskLine(task)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: Self.symbol(task.kind)) }
                        Spacer()
                        if let bytes = task.reclaimableBytes {
                            Text(ByteSize.format(bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(reclaimable > 0 ? "Cleanups · \(ByteSize.format(reclaimable)) Could Be Freed" : "Cleanups")
        } footer: {
            Text("Each figure is from that cleanup's last preview, not from the disk right now.")
        }
    }

    @ViewBuilder private var backupsSection: some View {
        if !backups.isEmpty {
            Section {
                ForEach(backups) { backup in
                    LabeledContent {
                        HStack {
                            Text(ByteSize.format(backup.sizeBytes)).monospacedDigit().foregroundStyle(.secondary)
                            Button("Show in Finder") { IOSBackups.revealInFinder(backup) }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(backup.deviceName)
                            if let last = StorageLog.ago(backup.lastBackup) {
                                Text("Last backed up \(last)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("iPhone and iPad Backups")
            } footer: {
                Text("Report only. Mac Analyzers never deletes a backup; remove one yourself in Finder if you no longer need it.")
            }
        }
    }

    // MARK: - behaviour

    private func taskLine(_ task: StorageTask) -> String {
        guard let when = task.measuredAt, let ago = StorageLog.ago(when) else { return task.detail }
        return "\(task.detail) Previewed \(ago)."
    }

    private static func symbol(_ kind: JobKind) -> String {
        switch kind {
        case .storageClean: "shippingbox"
        case .janitor: "arrow.down.circle"
        case .tempClean: "tray.full"
        case .spotlight: "magnifyingglass"
        default: "internaldrive"
        }
    }

    private func open(_ task: StorageTask) {
        let target: String = switch task.kind {
        case .storageClean: "caches"
        case .janitor: "downloads"
        case .tempClean: "temp"
        default: "spotlight"
        }
        navigator.open(target: target)
    }

    private func checkAll() {
        for kind in [JobKind.storageClean, .janitor, .tempClean, .spotlight] {
            store.enqueue(JobRequest(kind: kind, intent: .preview), trigger: .user)
        }
    }

    private func load() async {
        if let fixture {
            (usage, runway, runwayReason, tasks) = (fixture.usage, fixture.runway, fixture.reason, fixture.tasks)
            loaded = true
            return
        }
        let found = await Task.detached(priority: .userInitiated) {
            (LiveStats.diskUsage(), DiskRunway.outlook(DiskRunway.series()), StorageTasks.load(), IOSBackups.scan())
        }.value
        (usage, runway, runwayReason) = (found.0, found.1.runway, found.1.reason)
        (tasks, backups) = (found.2, found.3)
        loaded = true
    }
}
