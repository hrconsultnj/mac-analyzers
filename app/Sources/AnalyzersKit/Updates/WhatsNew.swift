import Foundation
import os

/// One feature of one release, as What's New shows it: the bullet of `CHANGELOG.md`, with the tag
/// the release author wrote at its end read into typed data (`WhatsNew+Parse.swift`).
public struct WhatsNewItem: Identifiable, Hashable, Sendable {

    /// Where the feature lives. A tagged bullet names a screen (`open=recordings`) or says it is a change
    /// across the app (`open=-`: the window, the sidebar); a bullet with no readable tag is `untagged`
    /// (every release before tags existed) and is grouped by its bold topic line instead.
    public enum Scope: Hashable, Sendable {
        case screen(String)
        case app
        case untagged
    }

    /// The version plus the bullet's position in its release: stable while the changelog is, and the route's payload.
    public let id: String
    /// "2.71.0"; nil for the unreleased section.
    public let version: String?
    public let released: Date?
    /// The release's title without its version: "Recording sources, one period menu…".
    public let releaseTitle: String
    /// The row's one line: the tag's title, or the bullet's first sentence.
    public let summary: String
    /// The title the tag gave, if it did (a name, in title style; `summary` is the first sentence otherwise).
    public let tagTitle: String?
    /// The whole bullet as prose, tag removed, Markdown as written.
    public let body: String
    public let scope: Scope
    /// An SF Symbol name from the tag.
    public let symbol: String?
    /// Reserved for a later version that shows a picture of the feature: read, kept, never shown yet.
    public let image: String?
    /// The bold line the bullet sat under: the fallback group of an untagged bullet.
    public let topic: String?
    /// True for the "Other Notes" row of a release: the paragraphs after its bullets, not a bullet.
    public let isNotes: Bool

    public init(id: String, version: String?, released: Date?, releaseTitle: String, summary: String, tagTitle: String?,
                body: String, scope: Scope, symbol: String?, image: String?, topic: String?, isNotes: Bool = false) {
        self.id = id; self.version = version; self.released = released; self.releaseTitle = releaseTitle
        self.summary = summary; self.tagTitle = tagTitle; self.body = body; self.scope = scope; self.symbol = symbol
        self.image = image; self.topic = topic; self.isNotes = isNotes
    }

    /// The deep-link target `Open <Screen>` goes to; nil for a change across the app and for an untagged bullet.
    public var target: String? {
        if case .screen(let target) = scope { target } else { nil }
    }
}

/// One release's What's New entry, from the changelog bundled with the app (the same
/// `CHANGELOG.md` each GitHub release publishes).
public struct ReleaseNote: Identifiable, Sendable {
    /// "v2.68.0 — See where all of your memory goes"
    public let title: String
    /// "2.68.0"; nil for the unreleased section.
    public let version: String?
    public let released: Date?
    /// The paragraphs before the first bullet: what the release is about.
    public let intro: [String]
    public let items: [WhatsNewItem]
    /// The paragraphs after the first bullet that are not topic lines: "Minor fixes and improvements throughout."
    public let closing: [String]
    /// The short name of a published beta ("2.72.1 Beta 2") when this is the card of one: the beta's own unreleased
    /// notes, `## Next` as it stood at its tag. nil for a release and for the clone's own unreleased section.
    public var betaLabel: String?

    public var id: String { title }
    /// What names this note in a route and in its features' ids: the version, "beta" for a beta's card, else "next".
    public var idPrefix: String { version ?? (betaLabel != nil ? "beta" : "next") }
    public var isUnreleased: Bool { version == nil }

    /// The title without "v2.68.0 — ".
    public var releaseTitle: String {
        guard let version else { return title }
        let rest = title.dropFirst(version.count + 1).drop { $0 == " " || $0 == "—" || $0 == "-" || $0 == ":" }
        return String(rest)
    }

    /// The same release under another name on screen (the channels name the unreleased section differently).
    public func renamed(_ title: String) -> ReleaseNote {
        ReleaseNote(title: title, version: version, released: released, intro: intro,
                    items: items.map { $0.renamed(releaseTitle: title) }, closing: closing, betaLabel: betaLabel)
    }

    /// The unreleased section as the card of a published beta: named by the beta ("2.72.1 Beta 2"), its features
    /// re-identified so they never collide with the clone's own unreleased section.
    public func asBeta(_ label: String) -> ReleaseNote {
        ReleaseNote(title: label, version: nil, released: nil, intro: intro,
                    items: items.map { $0.renamed(releaseTitle: label).reidentified(from: "next#", to: "beta#") },
                    closing: closing, betaLabel: label)
    }

    /// What the list shows for this release: its features, then one "Other Notes" row when the entry has paragraphs
    /// after its bullets (a "Fixed: …" note) that no feature carries, so nothing the old screen showed is lost.
    public var listedItems: [WhatsNewItem] { items + [notesItem].compactMap { $0 } }

    /// The feature-like row for `closing`; nil when there is none. Its screen shows the paragraphs.
    public var notesItem: WhatsNewItem? {
        guard !closing.isEmpty else { return nil }
        return WhatsNewItem(id: "\(idPrefix)#notes", version: version, released: released, releaseTitle: releaseTitle,
                            summary: Names.WhatsNew.notesFor(version), tagTitle: nil, body: closing.joined(separator: "\n\n"),
                            scope: .untagged, symbol: "note.text", image: nil, topic: Names.WhatsNew.otherNotes, isNotes: true)
    }

    /// What the unreleased section is called on screen.
    public static let unreleasedTitle = "In This Build — Not Yet Released"

    /// Each "## vX.Y…" heading starts one release; newest first, as written.
    ///
    /// A build ahead of the last release (`includeNext`) starts with what is in
    /// it and not yet released: the changelog's "## Next" section.
    public static func bundled(includeNext: Bool = false) -> [ReleaseNote] {
        guard let url = changelogURL else { return [] }
        return bundled(at: url, includeNext: includeNext)
    }

    private static var changelogURL: URL? {
        Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") ?? developmentFile.withLock { $0 }
    }

    /// When the changelog the notes are read from was last changed: what a cache of the parsed notes is keyed by.
    public static var changelogStamp: Date? {
        guard let url = changelogURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func bundled(at url: URL, includeNext: Bool) -> [ReleaseNote] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, includeNext: includeNext)
    }

    /// The changelog for a run that has no bundle (SnapshotRunner), named through
    /// `DeepLinkRouter.installFixtures(changelog:)`. The app people install always has the
    /// bundled file and nothing in it sets this: it reads no environment variable.
    private static let developmentFile = OSAllocatedUnfairLock<URL?>(initialState: nil)
    public static func useDevelopmentFile(_ url: URL?) { developmentFile.withLock { $0 = url } }

    /// The notes of every version an update brings: the releases after `installed` up to and including `offered`, newest
    /// first as the changelog writes them, from the changelog at the offered version's tag; and when `offered` is a beta,
    /// its own unreleased section named by `label`. `installed` and `offered` are internal versions ("2.72.1-beta.1").
    public static func forUpdate(changelog: String, installed: String, offered: String, label: String) -> [ReleaseNote] {
        let parsed = parse(changelog, includeNext: true)
        let releases = parsed.filter { note in
            guard let version = note.version else { return false }
            return UpdateChecker.isNewer(version, than: installed) && !UpdateChecker.isNewer(version, than: offered)
        }
        let isBeta = offered.contains("-beta.")
        guard isBeta, let next = parsed.first(where: { $0.isUnreleased }) else { return releases }
        return [next.asBeta(label)] + releases
    }

    /// The title of the clone's own unreleased section on This Copy.
    public static let notReleasedTitle = "Not Released Yet"

    /// The notes a channel's list shows, newest first.
    /// - Releases: the published releases. A development build also keeps its own bundled `## Next` as "In This Build —
    ///   Not Yet Released", and a beta build its own, named by the beta, so a copy always shows what it holds.
    /// - Beta: those, and the newest published beta's card (its `## Next` as it stood at its tag, `betaChangelog`, named by
    ///   `betaLabel`); a beta build that cannot read it (offline) shows the bundled one under its own name.
    /// - This Copy: those, and a "Not Released Yet" card from the clone's own `## Next` (`cloneChangelog`), which stands in
    ///   for the build's bundled one.
    /// A card that says exactly what another card says is left out.
    public static func channelNotes(channel: UpdateChannel, cloneChangelog: String?, betaChangelog: String?,
                                    betaLabel: String?, isDevelopment: Bool, runningBetaLabel: String?) -> [ReleaseNote] {
        let all = bundled(includeNext: isDevelopment || runningBetaLabel != nil)
        let released = all.filter { !$0.isUnreleased }
        let bundledNext = all.first { $0.isUnreleased }
        var cards: [ReleaseNote] = []
        func add(_ card: ReleaseNote) {
            if !cards.contains(where: { $0.items.map(\.body) == card.items.map(\.body) }) { cards.append(card) }
        }
        let cloneNext = channel == .thisCopy
            ? cloneChangelog.flatMap { parse($0, includeNext: true).first(where: { $0.isUnreleased }) } : nil
        if let cloneNext { add(cloneNext.renamed(notReleasedTitle)) }
        if isDevelopment, cloneNext == nil, let bundledNext { add(bundledNext.renamed(unreleasedTitle)) }
        if channel != .releases, let betaChangelog, let betaLabel,
           let next = parse(betaChangelog, includeNext: true).first(where: { $0.isUnreleased }) {
            add(next.asBeta(betaLabel))
        } else if let runningBetaLabel, let bundledNext {
            add(bundledNext.asBeta(runningBetaLabel))
        }
        return cards + released
    }

    /// The newest release that has shipped: what the sidebar card announces.
    public static func newestReleased(in notes: [ReleaseNote]) -> ReleaseNote? {
        notes.filter { !$0.isUnreleased }
            .max { UpdateChecker.compare($0.version ?? "0", $1.version ?? "0") == .orderedAscending }
    }
}

extension WhatsNewItem {
    func reidentified(from prefix: String, to replacement: String) -> WhatsNewItem {
        let newID = id.hasPrefix(prefix) ? replacement + id.dropFirst(prefix.count) : id
        return WhatsNewItem(id: newID, version: version, released: released, releaseTitle: releaseTitle, summary: summary,
                            tagTitle: tagTitle, body: body, scope: scope, symbol: symbol, image: image, topic: topic, isNotes: isNotes)
    }

    func renamed(releaseTitle: String) -> WhatsNewItem {
        WhatsNewItem(id: id, version: version, released: released, releaseTitle: releaseTitle, summary: summary, tagTitle: tagTitle,
                     body: body, scope: scope, symbol: symbol, image: image, topic: topic, isNotes: isNotes)
    }
}
