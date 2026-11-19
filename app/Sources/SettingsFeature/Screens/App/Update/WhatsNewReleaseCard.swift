import SwiftUI
import AnalyzersKit
import UIComponents

/// One release as a row of the What's New group on the Updates screen: its title, its version and how many features it brought, its date on
/// the right. The card of a published beta is named by the beta ("2.72.1 Beta 2") and says Beta where a release has its
/// date; the clone's unreleased section says "Not yet released". A card pushes that release's own screen, which lists its
/// features grouped by the screen they belong to.
struct WhatsNewReleaseCard: View {
    let note: ReleaseNote
    /// The release seen before this visit: later ones are marked New.
    let seen: String?
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Button { navigator.push(.app(.release(WhatsNewReleaseScreen.key(note)))) } label: {
            HStack(spacing: Tokens.Space.xl) {
                Label {
                    VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                        Text(note.isUnreleased ? note.title : note.releaseTitle).font(Tokens.Typography.rowTitleKey)
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    IconTile(symbol: symbol, color: color, side: 28)
                }
                .labelStyle(.centeredIcon)
                Spacer(minLength: Tokens.Space.xl)
                if WhatsNewSeen.isNew(note.version, seen: seen) {
                    Text(Names.WhatsNew.new).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
                Text(trailing).font(.callout).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.vertical, Tokens.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this release")
    }

    private var symbol: String { note.betaLabel != nil ? "testtube.2" : (note.isUnreleased ? "hammer.fill" : "sparkles") }
    private var color: Color { note.betaLabel != nil ? .purple : (note.isUnreleased ? .blue : .orange) }

    private var trailing: String {
        if note.betaLabel != nil { return Names.Channel.beta }
        return note.released.map { $0.formatted(.dateTime.day().month(.abbreviated)) }
            ?? (note.isUnreleased ? Names.WhatsNew.notYetReleased : "")
    }

    /// "v2.72.0 · 7 new features".
    private var line: String {
        let features = Names.WhatsNew.featureCount(note.listedItems.count)
        return note.version.map { "v\($0) · \(features)" } ?? features
    }
}

/// The notes this copy holds and has not shipped, as one short row on the update card rather than a full
/// What's New card. Two lines are shown; the tooltip names each screen, and the row opens that release.
struct HeldNotesRow: View {
    let note: ReleaseNote
    @Environment(Navigator.self) private var navigator

    private var groups: [WhatsNewGroup] { WhatsNewGroups.build(items: note.listedItems) }

    /// The first screens, and how many did not fit on the row.
    private var preview: String {
        let screens = groups.map(\.title)
        let head = screens.prefix(2).joined(separator: ", ")
        if head.isEmpty { return Names.WhatsNew.featureCount(note.listedItems.count) }
        let more = screens.count - 2
        return more > 0 ? "\(head), and \(more) more" : head
    }

    /// Every screen and the features on it: what the row does not have room to show.
    private var tip: String {
        groups.map { group in
            let names = group.items.map { $0.tagTitle ?? $0.summary }.joined(separator: ", ")
            return "\(group.title) — \(names)"
        }.joined(separator: "\n")
    }

    var body: some View {
        Button { navigator.push(.app(.release(WhatsNewReleaseScreen.key(note)))) } label: {
            VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                Text(note.title).font(.callout.weight(.semibold))
                // two lines: the rest is the tooltip, and the screen this row opens
                Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .help(tip.isEmpty ? note.title : tip)
        .accessibilityHint("Opens \(note.title)")
    }
}
