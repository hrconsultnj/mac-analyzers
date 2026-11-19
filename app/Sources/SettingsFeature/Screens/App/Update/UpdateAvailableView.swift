import SwiftUI
import AppKit
import AnalyzersKit
import UIComponents

/// The window "Check for Updates" opens when something newer is out, in the shape people know from Sparkle and OrbStack: the
/// app's icon, "A new version of Sparehold is available!", what is available and what you have, the notes of every
/// version in between (newest first), and three buttons: Skip This Version, Remind Me Later, Install Update.
public struct UpdateAvailableView: View {
    let offered: String
    let installed: String
    let notes: [ReleaseNote]
    let skip: () -> Void
    let remindLater: () -> Void
    let install: () -> Void

    public init(offered: String, installed: String, notes: [ReleaseNote], skip: @escaping () -> Void,
                remindLater: @escaping () -> Void, install: @escaping () -> Void) {
        self.offered = offered; self.installed = installed; self.notes = notes
        self.skip = skip; self.remindLater = remindLater; self.install = install
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            HStack(alignment: .top, spacing: Tokens.Space.xl) {
                // fixed: the app's icon is the one thing here that has a size of its own
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text(Names.Update.available).font(.headline)
                    Text(Names.Update.wouldYouLikeToUpdate(new: offered, installed: installed))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !notes.isEmpty {
                GroupBox {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Tokens.Space.l) {
                            ForEach(notes) { note in
                                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                    Text(heading(note)).font(.subheadline.weight(.semibold))
                                    ForEach(note.listedItems, id: \.id) { item in
                                        Label {
                                            VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                                                Text(item.summary).fixedSize(horizontal: false, vertical: true)
                                                // the feature's own one-line description, as the release screen shows it
                                                if let line = WhatsNewText.description(item) {
                                                    Text(WhatsNewText.styled(line))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        } icon: {
                                            Image(systemName: item.symbol ?? "sparkles").foregroundStyle(.secondary)
                                        }
                                        .labelStyle(.centeredIcon)
                                        .font(.callout)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Tokens.Space.m)
                    }
                    .frame(height: 220)      // fixed: a scroll region has no height of its own
                } label: {
                    Text(Names.Update.releaseNotes).font(.subheadline.weight(.semibold))
                }
            }
            HStack {
                Button(Names.Update.skipThisVersion, action: skip)
                Spacer()
                Button(Names.Update.remindMeLater, action: remindLater)
                Button(Names.Update.installUpdate, action: install)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 520)      // fixed: the window's own width
    }

    /// "v2.73.0 — Title", or the beta's name for its unreleased notes.
    private func heading(_ note: ReleaseNote) -> String {
        guard let version = note.version else { return note.title }
        let title = note.releaseTitle
        return title.isEmpty ? "v\(version)" : "v\(version) — \(title)"
    }
}
