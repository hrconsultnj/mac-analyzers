import SwiftUI
import AnalyzersKit
import UIComponents

/// The Updates screen, in the order of System Settings → Software Update: the status and Check for Updates, then
/// Check Automatically on that same card, then where updates come from (Releases, Beta, This Copy — the beta choice),
/// then What's New. The channel that is selected is the one Install updates from. A clone runs that update in the
/// background and the lines appear on this card; the app closes and opens again when it finishes. A downloaded copy
/// opens the latest release on GitHub. Sparkle is not in this build.
struct UpdateSettingsView: View {

    @Environment(UpdateState.self) private var updates

    @Environment(Navigator.self) private var navigator

    /// What's New, under the controls: the list follows the channel picked above (`WhatsNewSource`).
    @State private var notes: [ReleaseNote] = []
    @State private var loaded = false
    /// The release seen before this visit, read once: opening the screen marks what is installed as seen, and the
    /// "New" marks on the cards must still say what had not been.
    @State private var seenBefore: String?

    // The latest release, whether one is newer and whether a check is running all come from the app's one
    // update state, so a check made here also reaches the sidebar, Overview and the menu-bar panel.
    private var installed: String { updates.installed }
    private var latest: String? { updates.latest }
    private var checking: Bool { updates.phase == .checking }
    private var updateAvailable: Bool { updates.isAvailable }

    private var installTitle: String {
        switch updates.channel {
        case .releases: Names.Update.installUpdate
        case .beta: Names.Channel.installBeta
        case .thisCopy: Names.Channel.rebuild
        }
    }

    /// Releases this copy already contains. A newer published version is an update, not a What's New card.
    private var installedNotes: [ReleaseNote] {
        notes.filter { note in
            guard let version = note.version else { return false }
            return !UpdateChecker.isNewer(version, than: installed)
        }
    }

    /// What this copy holds that has not shipped: "Not Released Yet" on This Copy, otherwise the build's own
    /// unreleased notes. A beta you could install, and are not running, is not this.
    private var heldNote: ReleaseNote? {
        notes.first { $0.title == ReleaseNote.notReleasedTitle || $0.title == ReleaseNote.unreleasedTitle }
    }

    private func scrollIfAsked(_ proxy: ScrollViewProxy) {
        guard loaded, navigator.pendingIntent?.section == AppGroup.updates,
              navigator.takeIntent(for: AppGroup.updates) == "whatsNew" else { return }
        withAnimation { proxy.scrollTo(WhatsNewSections.anchor, anchor: .top) }
    }

    var body: some View {
        DataScreen(title: Names.Screen.updates, subtitle: updates.build.versionText) {
        ScrollViewReader { proxy in
        Form {
            Section {
                UpdateStatusCard(updates: updates, installTitle: installTitle)
                if let held = heldNote {
                    HeldNotesRow(note: held)
                }
                if updates.phase == .installing || updates.installFailed || !updates.installLines.isEmpty {
                    UpdateInstallLog(updates: updates)
                }
                AutomaticChecksRow(updates: updates)
            }
            UpdateChannelSection(updates: updates, checking: checking)
            Section {
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if installedNotes.isEmpty {
                    Text(Names.WhatsNew.notInTheseNotes).foregroundStyle(.secondary)
                } else {
                    ForEach(installedNotes) { note in
                        WhatsNewReleaseCard(note: note, seen: seenBefore)
                    }
                }
            } header: {
                Label(Names.WhatsNew.title, systemImage: "sparkles").font(.headline)
            }
            .id(WhatsNewSections.anchor)
        }
        .formStyle(.grouped)
        // a link to the list (`updates:whatsNew`) scrolls to it once the screen is showing and the list is loaded
        .onChange(of: navigator.pendingIntent) { scrollIfAsked(proxy) }
        .onAppear { scrollIfAsked(proxy) }
        .onChange(of: loaded) { scrollIfAsked(proxy) }
        }
        }
        .task {
            // always fresh when the pane opens — the cache is for background
            // polling, not for the screen whose job is showing the truth
            await updates.check(force: true)
        }
        .task(id: "\(updates.channel.rawValue)|\(updates.channelChangelog?.hashValue ?? 0)|\(updates.betaNotes?.label ?? "")") {
            if seenBefore == nil {
                await WhatsNewSeen.migrate(installed: installed)
                seenBefore = WhatsNewSeen.version ?? ""
                // being on this screen is seeing what the installed version brought
                WhatsNewSeen.markSeen(installed)
            }
            notes = await WhatsNewSource.notes(updates: updates)
            loaded = true
        }
    }
}
