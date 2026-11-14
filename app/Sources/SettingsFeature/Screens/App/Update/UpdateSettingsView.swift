import SwiftUI
import AnalyzersKit
import UIComponents

/// Update pane: installed vs latest release, one-click upgrade via the
/// repo's upgrade.command (runs in Terminal so progress is visible).
struct UpdateSettingsView: View {

    @Environment(UpdateState.self) private var updates

    @State private var notes: [ReleaseNote] = []
    /// Which entries the reader opened or closed, by entry id.
    @State private var expanded: [String: Bool] = [:]

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
            "Install opens Terminal and runs upgrade.command: pulls the latest version, rebuilds the app, refreshes the background agents, and relaunches. Your settings and protected lists are never touched."
        case .beta:
            "Updating opens Terminal and runs upgrade.command on your clone: pulls the newest commit on the development branch, rebuilds the app, refreshes the background agents, and relaunches. It never happens by itself. Your settings and protected lists are never touched."
        case .thisCopy:
            "Rebuilding opens Terminal and runs rebuild.command: builds your clone as it is, uncommitted changes included, refreshes the background agents, and relaunches. Nothing is pulled. Your settings and protected lists are never touched."
        }
    }

    var body: some View {
        DataScreen(title: Names.Screen.updates, subtitle: updates.build.versionText) {
        List {
            UpdateChannelSection(updates: updates, checking: checking)
            Section {
                LabeledContent("Installed Version") { Text(updates.build.versionText).monospacedDigit() }
                if let build = UpdateChecker.installedBuild {
                    LabeledContent("Build") {
                        Text(build)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .help("The exact build of this copy; the version changes only on release")
                }
                if updates.channel == .releases {
                    LabeledContent("Latest Release") {
                        Text(latest.map { "v\($0)" } ?? (checking ? "Checking…" : "—"))
                            .monospacedDigit()
                    }
                    if updateAvailable {
                        Label(Names.State.updateAvailable, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else if updates.build.isDevelopment {
                        Label(updates.build.developmentSentence(latest: latest), systemImage: "hammer.fill")
                            .foregroundStyle(.blue)
                    } else if latest != nil {
                        Label(Names.State.upToDate, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    UpdateChannelRows(updates: updates, checking: checking)
                }
            }
            Section {
                HStack {
                    Button(checking ? "Checking…" : "Check Now") {
                        Task { await updates.check(force: true) }
                    }
                    .disabled(checking)
                    Spacer()
                    Button(installTitle) { updates.requestInstall() }
                        .buttonStyle(.glassProminent)
                        .disabled(!updateAvailable)
                }
                Text(installExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !notes.isEmpty {
                Section("What's New") {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        // one disclosed block, not rows: a release's notes open as one body
                        DisclosureGroup(isExpanded: expansion(of: note, isNewest: index == 0)) {
                            ReleaseNoteBody(note: note)
                        } label: {
                            Text(note.title)
                                .font(.callout.weight(.medium))
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        }
        .task(id: "\(updates.channel.rawValue)\(updates.channelChangelog?.count ?? 0)") {
            UserDefaults.standard.set(installed, forKey: "lastSeenChangelog")
            let channel = updates.channel
            let channelText = updates.channelChangelog
            // Beta and This Copy read the unreleased section from THEIR changelog (development's, or the
            // clone's with its uncommitted edits); the releases below are the bundled ones.
            let includeNext = channel == .releases && updates.build.isDevelopment
            await awaitLoad({ ReleaseNote.channelNotes(channel: channel, changelog: channelText, includeNext: includeNext) }) { notes = $0 }
        }
        .task {
            // always fresh when the pane opens — the cache is for background
            // polling, not for the screen whose job is showing the truth
            await updates.check(force: true)
        }
    }

    /// The newest entry starts open; every entry can be opened and closed.
    /// (The binding used to be a constant, so older releases could never be
    /// read at all — their arrows did nothing.)
    private func expansion(of note: ReleaseNote, isNewest: Bool) -> Binding<Bool> {
        Binding(
            get: { expanded[note.id] ?? isNewest },
            set: { expanded[note.id] = $0 })
    }
}
