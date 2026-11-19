import SwiftUI
import AnalyzersKit

/// One release on its own screen: its features, grouped by the screen they belong to (the unreleased section on its own),
/// each a row that pushes the feature's screen.
struct WhatsNewReleaseScreen: View {
    /// The release's version, "next" for the unreleased section, "beta" for the published beta's card, or "latest" for the newest one that shipped.
    let version: String

    @Environment(UpdateState.self) private var updates
    @State private var notes: [ReleaseNote] = []
    @State private var loaded = false

    /// What names `note` in a route.
    static func key(_ note: ReleaseNote) -> String { note.idPrefix }

    private var note: ReleaseNote? {
        switch version {
        case "latest": ReleaseNote.newestReleased(in: notes)
        default: notes.first { Self.key($0) == version }
        }
    }

    var body: some View {
        Group {
            if let note {
                List { WhatsNewSections(notes: [note], filter: .all, seen: nil) }
                    .listStyle(.inset)
                    .navigationTitle(note.version.map { "v\($0)" } ?? note.title)
                    .navigationSubtitle(note.isUnreleased ? "" : note.releaseTitle)
            } else if loaded {
                EmptyState(Names.WhatsNew.featureNotFound, systemImage: "sparkles", description: Text(Names.WhatsNew.notInTheseNotes))
            } else {
                LoadingState()
            }
        }
        .task {
            notes = await WhatsNewSource.notes(updates: updates)
            loaded = true
        }
    }
}
