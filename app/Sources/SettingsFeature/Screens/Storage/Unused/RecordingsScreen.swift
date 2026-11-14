import AnalyzersKit
import SwiftUI

/// Old Recordings: recordings older than your limit, from every place your recording apps save to. Each source that
/// found something is a tab (Zoom, Screen Recordings, a folder of yours), and the recordings in it are grouped by the
/// day they were made. Where to look, and how old a recording has to be, are set in one window, Sources…, which the
/// toolbar, the empty screen and (with Setup's rebuild) Setup all open.
struct RecordingsScreen: View {
    @State private var model = StorageReviewModel()
    @State private var showSources = false
    @Environment(ConfigStore.self) private var config
    @Environment(JobStore.self) private var store
    @Environment(Navigator.self) private var navigator
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?
    /// `SnapshotRunner`: the screen as it is with no source switched on.
    var fixtureNoneOn = false

    private var days: Int { config.storage.recordingsDays }

    /// What the screen looks through, in words: the apps by name, the person's own folders as a count.
    private var looksThrough: [String] {
        let entries = config.storage.recordingSources
        guard !entries.isEmpty else {
            return config.storage.recordingSourcesConfigured || config.storage.recordingsDir.isEmpty ? [] : ["1 folder of yours"]
        }
        let on = entries.filter(\.enabled)
        let apps = on.filter { !$0.isCustom }.compactMap { RecordingSourceCatalog.definition($0.id)?.title }
        let own = on.filter(\.isCustom).count
        return apps + (own > 0 ? ["\(own) \(own == 1 ? "folder" : "folders") of yours"] : [])
    }

    private var noneOn: Bool { fixtureNoneOn || (fixture == nil && looksThrough.isEmpty) }

    private var emptyText: String {
        if noneOn { return "Choose where your recording apps save, and Mac Analyzers looks for recordings older than \(days) days." }
        let names = fixture != nil && looksThrough.isEmpty ? ["Zoom", "Screen Recordings", "1 folder of yours"] : looksThrough
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : names.first ?? ""
        return "Looks through \(list) for recordings older than \(days) days. Nothing is removed until you review it."
    }

    /// What the newest preview found in each source, for the Sources window.
    private var found: [String: RecordingFound] {
        guard let rows = model.rows else { return [:] }
        var result: [String: RecordingFound] = [:]
        for row in rows.rows where row.isChoosable {
            var entry = result[row.category] ?? RecordingFound(count: 0, bytes: 0)
            entry.count += 1
            entry.bytes += row.bytes ?? 0
            result[row.category] = entry
        }
        return result
    }

    var body: some View {
        StorageReviewScreen<StorageTab>(
            model: model, title: Names.Screen.oldRecordings, kind: .recordings, screenKey: "recordings",
            options: JobOptions(recordingsDays: days),
            parse: { UnusedReview.recordings(lines: $0.lines) },
            applyTitle: "Move to Trash",
            confirmation: ReviewConfirmation(
                verb: "Move", destination: "to the Trash",
                message: "These recordings are older than \(days) days. You can put them back from Undo, and the space returns when the Trash is emptied.",
                permanent: nil, namesRows: "Recordings to move"),
            emptyText: emptyText,
            emptyTitle: noneOn ? Names.Recordings.noFoldersChosen : "No Preview Yet",
            destination: Names.Review.goesToTrash,
            emptyActions: [ReviewAction(id: "choose", title: Names.Recordings.chooseFolders, systemImage: "folder.badge.gearshape",
                                        help: "Choose where your recording apps save", action: { showSources = true })],
            toolbarActions: [ReviewAction(id: "sources", title: Names.Recordings.sourcesButton, systemImage: "folder.badge.gearshape",
                                          help: "Choose which folders Old Recordings looks in, and how old a recording has to be",
                                          action: { showSources = true })],
            previewDisabledReason: noneOn ? "Choose which folders to look in first" : nil,
            emptySymbol: noneOn ? "folder.badge.questionmark" : "eye")
            .onAppear { if let fixture { model.showFixture(fixture) } }
            .recordingSourcesSheet(isPresented: $showSources, found: found, previewed: model.rows != nil) {
                // the sources changed, so the review on screen is of the old ones: throw it away and say to preview again
                if model.phase == .ready { model.discard(store) }
            }
            .onChange(of: navigator.pendingIntent) { applyPendingLink() }
            .task { applyPendingLink() }
    }

    /// `recordings:sources` opens the window: navigation only, it starts nothing.
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: StorageGroup.recordings) else { return }
        if payload == "sources" { showSources = true }
    }
}
