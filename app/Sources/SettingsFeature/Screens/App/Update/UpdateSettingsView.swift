import SwiftUI
import AnalyzersKit
import UIComponents

/// The Updates screen: a status card in the shape of the system's Software Update, then where updates come from (Releases,
/// Beta, This Copy) and whether the app checks by itself, then What's New, which follows the channel. Installing runs the
/// repo's upgrade.command (in Terminal, so progress is visible) and always asks first.
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
        case .releases: "Install Update…"
        case .beta: Names.Channel.installBeta + "…"
        case .thisCopy: Names.Channel.rebuild + "…"
        }
    }

    private var installExplanation: String {
        switch updates.channel {
        case .releases:
            "Install opens Terminal and runs upgrade.command on your clone: it pulls the newest version of the branch your clone is on (on main, the newest release), rebuilds the app, refreshes the background agents, and relaunches. Your settings and protected lists are never touched."
        case .beta:
            "Updating opens Terminal and runs beta.command on your clone: it moves your clone to the newest beta (or to the newer release, once one is out), rebuilds the app, refreshes the background agents, and relaunches. It never happens by itself. Your settings and protected lists are never touched."
        case .thisCopy:
            "Rebuilding opens Terminal and runs rebuild.command: builds your clone as it is, uncommitted changes included, refreshes the background agents, and relaunches. Nothing is pulled. Your settings and protected lists are never touched."
        }
    }

    private func scrollIfAsked(_ proxy: ScrollViewProxy) {
        guard loaded, navigator.pendingIntent?.section == AppGroup.updates,
              navigator.takeIntent(for: AppGroup.updates) == "whatsNew" else { return }
        withAnimation { proxy.scrollTo(WhatsNewSections.anchor, anchor: .top) }
    }

    var body: some View {
        DataScreen(title: Names.Screen.updates, subtitle: updates.build.versionText) {
        ScrollViewReader { proxy in
        List {
            Section { UpdateStatusCard(updates: updates, installTitle: installTitle) }
            UpdateChannelSection(updates: updates, checking: checking, installExplanation: installExplanation)
            AutomaticChecksRow(updates: updates)
            Section {
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if notes.isEmpty {
                    Text(Names.WhatsNew.notInTheseNotes).foregroundStyle(.secondary)
                } else {
                    ForEach(notes) { note in
                        WhatsNewReleaseCard(note: note, seen: seenBefore)
                            .listRowSeparator(.hidden)
                    }
                }
            } header: {
                Label(Names.WhatsNew.title, systemImage: "sparkles").font(.headline)
            }
            .id(WhatsNewSections.anchor)
        }
        .listStyle(.inset)
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
