import SwiftUI
import AnalyzersKit
import UIComponents

/// Which releases the What's New list shows: a filter (the same rows, fewer), so a toolbar menu and not tabs.
enum WhatsNewFilter: String, CaseIterable, Identifiable {
    case all, latest
    var id: String { rawValue }
    var title: String { self == .all ? Names.WhatsNew.allReleases : Names.WhatsNew.latestRelease }
    var symbol: String { self == .all ? "clock.arrow.circlepath" : "sparkles" }
}

/// Where the notes behind What's New come from, shared by the list and each release's and feature's screen so all read the
/// same releases.
///
/// Parsing the changelog takes a fraction of a second, so it does not go through the shared load queue
/// (`awaitLoad`): that queue runs one expensive read at a time (Overview's trends, the process table) and What's
/// New used to wait behind whatever was running, seconds on the first open after launch. It is read off the main
/// thread, once for each channel, changelog text and modification date of the bundled file, and kept.
@MainActor
enum WhatsNewSource {
    private struct Key: Hashable {
        let channel: UpdateChannel
        let cloneText: Int
        let betaText: Int
        let betaLabel: String?
        let isDevelopment: Bool
        let runningBeta: String?
        let stamp: Date?
    }
    private static var cache: [Key: [ReleaseNote]] = [:]

    /// The list of the channel in use (`ReleaseNote.channelNotes`): Releases the published releases, Beta those and the
    /// newest published beta, This Copy those and the clone's own "Not Released Yet"; a Dev or beta build also keeps the
    /// notes it holds. Kept per channel, so switching
    /// the tab shows the list at once.
    static func notes(updates: UpdateState) async -> [ReleaseNote] {
        let channel = updates.channel
        let clone = updates.channelChangelog
        let beta = updates.betaNotes
        let isDevelopment = updates.build.isDevelopment
        let runningBeta = updates.build.isBeta ? updates.build.label : nil
        let key = Key(channel: channel, cloneText: clone.hashValue, betaText: beta?.changelog.hashValue ?? 0,
                      betaLabel: beta?.label, isDevelopment: isDevelopment, runningBeta: runningBeta, stamp: ReleaseNote.changelogStamp)
        if let hit = cache[key] { return hit }
        let parsed = await Task.detached(priority: .userInitiated) {
            ReleaseNote.channelNotes(channel: channel, cloneChangelog: clone, betaChangelog: beta?.changelog, betaLabel: beta?.label,
                                     isDevelopment: isDevelopment, runningBetaLabel: runningBeta)
        }.value
        cache[key] = parsed
        return parsed
    }
}

/// The What's New sections of the Updates list: what is not yet released first, then the features of the
/// releases grouped by the screen they belong to, each a row that pushes its own screen. Returns sections, so it
/// goes inside the screen's `List`.
struct WhatsNewSections: View {
    let notes: [ReleaseNote]
    let filter: WhatsNewFilter
    /// The release the person had seen before this visit: later ones are marked New.
    let seen: String?

    /// The id of the first row, which a link to the list scrolls to.
    static let anchor = "whatsNew"

    @Environment(Navigator.self) private var navigator
    /// Features shown at once: a list never gains more than 200 rows in one update.
    @State private var limit = 200

    var body: some View {
        let unreleased = notes.filter(\.isUnreleased)
        let shown = releasedItems
        let capped = Array(shown.prefix(limit))
        // grouped once per render: the first row, which a link scrolls to, is found from these and not by every row
        let groups = WhatsNewGroups.build(items: capped)
        let first = unreleased.first?.listedItems.first?.id ?? groups.first?.items.first?.id
        ForEach(unreleased) { note in
            Section {
                rows(note.listedItems, first: first)
            } header: {
                header(title: note.title, symbol: "hammer", count: note.listedItems.count)
            }
        }
        ForEach(groups) { group in
            Section {
                rows(group.items, first: first)
            } header: {
                header(title: group.title, symbol: group.symbol, count: group.items.count)
            }
        }
        if shown.count > capped.count {
            Button { limit += 200 } label: {
                Label(Names.Raw.showOlder, systemImage: "clock.arrow.circlepath")
                Text(Names.WhatsNew.earlierFeatures(shown.count - capped.count)).foregroundStyle(.secondary)
            }
        }
    }

    /// The released features, newest release first, narrowed by the filter.
    private var releasedItems: [WhatsNewItem] {
        let released = notes.filter { !$0.isUnreleased }
        let chosen = filter == .latest ? Array(released.prefix(1)) : released
        return chosen.flatMap(\.listedItems)
    }

    private func rows(_ items: [WhatsNewItem], first: String?) -> some View {
        ForEach(items) { item in
            WhatsNewRow(item: item, isNew: WhatsNewSeen.isNew(item.version, seen: seen)) {
                navigator.push(.app(.whatsNew(item.id)))
            }
            .id(item.id == first ? Self.anchor : item.id)
        }
    }

    private func header(title: String, symbol: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.headline)
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
