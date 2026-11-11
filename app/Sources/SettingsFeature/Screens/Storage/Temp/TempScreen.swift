import AnalyzersKit
import SwiftUI

/// Temp & Agents: what fills the temp folders and the folders AI coding tools keep, named for
/// what it is, with what the cleanup leaves alone shown beside it and why.
struct TempScreen: View {
    @State private var model = StorageReviewModel()
    @State private var permanent = false
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?
    @State private var ejecting: StorageRow?
    @State private var ejection: Job?
    @Environment(JobStore.self) private var store

    /// The images mounted from temp folders, as the review found them.
    private var images: [StorageRow] { model.rows?.rows(in: TempCategory.diskImages) ?? [] }

    var body: some View {
        StorageReviewScreen<TempCategory>(
            model: model, title: Names.Screen.tempAndAgents, kind: .tempClean, screenKey: "temp",
            options: JobOptions(permanent: permanent),
            parse: { TempReview.build(from: TempCleanParser.parse(runHeader: $0.banner, lines: $0.lines)).rows },
            lastKnownMatches: { [permanent] in $0.banner.contains("permanent") == permanent },
            applyTitle: permanent ? "Delete" : "Move to Trash",
            confirmation: permanent
                ? ReviewConfirmation(verb: "Delete", destination: "permanently",
                                     message: "Nothing here is open, recent, live or someone else's.",
                                     permanent: "Deleted items can't be put back.")
                : ReviewConfirmation(verb: "Move", destination: "to the Trash",
                                     message: "You can put them back from Undo. The space returns when the Trash is emptied.",
                                     permanent: nil),
            emptyText: "Looks through /tmp, your temp folder, /var/tmp and the folders Claude Code, Codex and other AI tools keep. Nothing open, recent, live or someone else's is ever touched.")
            .toolbar {
                ToolbarItem {
                    Picker("Clear To", selection: $permanent) {
                        Text("Trash").tag(false)
                        Text("Delete Permanently").tag(true)
                    }
                    .pickerStyle(.menu)
                    .help("Where cleared items go")
                }
                .toolbarRank(.secondary)
                ToolbarItem {
                    if !images.isEmpty {
                        Menu {
                            ForEach(images) { image in Button(image.title) { ejecting = image } }
                        } label: { Label("Eject", systemImage: "eject") }
                        .help("Eject a disk image mounted from a temp folder")
                    }
                }
                .toolbarRank(.secondary)
            }
            .onChange(of: permanent) { model.discard(store) }
            .onAppear { if let fixture { model.showFixture(fixture) } }
            .confirmationDialog("Eject \(ejecting?.title ?? "Disk Image")?", isPresented: Binding(
                get: { ejecting != nil }, set: { if !$0 { ejecting = nil } }), titleVisibility: .visible) {
                Button("Eject") { eject() }
            } message: {
                Text("Closes the disk image. Nothing is deleted, and you can open the image file again any time. If something is still reading from it, macOS refuses and nothing changes.")
            }
            // the images are listed from the preview: once one is ejected, look again
            .task(id: JobStamp(ejection)) {
                if let ejection, case .succeeded = ejection.state { self.ejection = nil; model.startPreview(store, kind: .tempClean, options: JobOptions(permanent: permanent)) }
            }
    }

    private func eject() {
        guard let image = ejecting else { return }
        ejecting = nil
        ejection = store.enqueue(JobRequest(kind: .eject, intent: .run, options: JobOptions(mountPoint: image.id)), trigger: .user)
    }
}
