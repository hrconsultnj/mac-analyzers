import AnalyzersKit
import SwiftUI

/// Temp & Agents: what fills the temp folders and the folders AI coding tools keep, named for
/// what it is, with what the cleanup leaves alone shown beside it and why.
struct TempScreen: View {
    @State private var model = StorageReviewModel()
    /// The person's own pick for the next preview; nil until they pick. What the screen SHOWS
    /// (`permanent`) comes from the preview on screen: an Apply runs with the preview's setting.
    @State private var chosen: Bool?
    /// Example rows for `SnapshotRunner`; nil in the app.
    var fixture: StorageRows?
    @State private var ejecting: StorageRow?
    @State private var ejection: Job?
    @Environment(JobStore.self) private var store

    /// The images mounted from temp folders, as the review found them.
    private var images: [StorageRow] { model.rows?.rows(in: TempCategory.diskImages) ?? [] }

    private var permanent: Bool {
        model.setting(kind: .tempClean, chosen: JobOptions(permanent: chosen ?? false)).permanent
    }

    private var permanentBinding: Binding<Bool> {
        Binding(get: { permanent }, set: { picked in
            if model.pick(JobOptions(permanent: picked), kind: .tempClean, chosen: JobOptions(permanent: chosen ?? false), store) {
                chosen = picked
            }
        })
    }

    var body: some View {
        let words = model.words(kind: .tempClean, chosen: JobOptions(permanent: chosen ?? false))
        StorageReviewScreen<TempCategory>(
            model: model, title: Names.Screen.tempAndAgents, kind: .tempClean, screenKey: "temp",
            // a new preview starts with the app's own pick; only SHOWING an existing preview (one made in
            // Terminal, or by the schedule) follows that preview's setting
            options: model.phase == .lastKnown ? JobOptions(permanent: chosen ?? false) : JobOptions(permanent: permanent),
            parse: { TempReview.build(from: TempCleanParser.parse(runHeader: $0.banner, lines: $0.lines)).rows },
            lastKnownMatches: { [picked = chosen] block in
                picked.map { StorageSetting.options(kind: .tempClean, banner: block.banner).permanent == $0 } ?? true
            },
            applyTitle: words.applyTitle,
            confirmation: ReviewConfirmation(words: words),
            emptyText: "Looks through /tmp, your temp folder, /var/tmp and the folders Claude Code, Codex and other AI tools keep. Nothing open, recent, live or someone else's is ever touched.",
            destination: permanent ? Names.Review.deletedPermanently : Names.Review.goesToTrash)
            .toolbar {
                ToolbarItem {
                    // a menu whose label is the current choice, icon and title: where cleared items go is always in view
                    Menu {
                        Picker("Clear To", selection: permanentBinding) {
                            Label("Trash", systemImage: "trash").tag(false)
                            Label("Delete Permanently", systemImage: "trash.slash").tag(true)
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(permanent ? "Delete Permanently" : "Trash", systemImage: permanent ? "trash.slash" : "trash")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Where cleared items go")
                }
                .toolbarRank(.primary)
                ToolbarItem {
                    if !images.isEmpty {
                        Menu {
                            ForEach(images) { image in Button(image.title) { ejecting = image } }
                        } label: { Label("Eject", systemImage: "eject") }
                        .labelStyle(.titleAndIcon)
                        .help("Eject a disk image mounted from a temp folder")
                    }
                }
                .toolbarRank(.secondary)
            }
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
