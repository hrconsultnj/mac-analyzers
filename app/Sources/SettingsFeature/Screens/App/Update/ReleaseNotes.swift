import os
import SwiftUI
import AnalyzersKit
import UIComponents

/// One release's What's New entry, from the changelog bundled with the app
/// (the same `CHANGELOG.md` each GitHub release publishes).
struct ReleaseNote: Identifiable {

    /// A piece of an entry as it should READ: the file is hard-wrapped at 78
    /// columns for editing, but on screen a paragraph is one flowing
    /// paragraph and a list item is one item.
    enum Block: Identifiable {
        case paragraph(String)
        case bullet(String)

        var id: String {
            switch self {
            case .paragraph(let text): "p:\(text)"
            case .bullet(let text): "b:\(text)"
            }
        }
    }

    /// "v2.68.0 — See where all of your memory goes"
    let title: String
    let blocks: [Block]
    var id: String { title }

    /// Each "## vX.Y…" heading starts one release; newest first, as written.
    ///
    /// A build ahead of the last release (`includeNext`) starts with what is in
    /// it and not yet released: the changelog's "## Next" section.
    static func bundled(includeNext: Bool = false) -> [ReleaseNote] {
        let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") ?? developmentFile.withLock { $0 }
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, includeNext: includeNext)
    }

    /// The changelog for a run that has no bundle (SnapshotRunner), named through
    /// `DeepLinkRouter.installFixtures(changelog:)`. The app people install always has the
    /// bundled file and nothing in it sets this: it reads no environment variable.
    private static let developmentFile = OSAllocatedUnfairLock<URL?>(initialState: nil)
    static func useDevelopmentFile(_ url: URL?) { developmentFile.withLock { $0 = url } }

    /// The notes for a channel: Releases as always; Beta and This Copy start with the "## Next" section of the
    /// changelog they follow (what is on development, what is in the clone), then the bundled releases.
    static func channelNotes(channel: UpdateChannel, changelog: String?, includeNext: Bool) -> [ReleaseNote] {
        let released = bundled(includeNext: includeNext)
        guard channel != .releases, let changelog,
              let next = parse(changelog, includeNext: true).first(where: { $0.title == unreleasedTitle })
        else { return released }
        let title = channel == .beta ? "On Development — Not Yet Released" : "In Your Clone — Not Yet Released"
        return [ReleaseNote(title: title, blocks: next.blocks)] + released.filter { $0.title != unreleasedTitle }
    }

    /// What the unreleased section is called on screen.
    static let unreleasedTitle = "In This Build — Not Yet Released"

    static func parse(_ changelog: String, includeNext: Bool = false) -> [ReleaseNote] {
        changelog.components(separatedBy: "\n## ")
            .map { $0.hasPrefix("## ") ? String($0.dropFirst(3)) : $0 }
            .filter { $0.hasPrefix("v") || (includeNext && $0.hasPrefix("Next")) }
            .compactMap { section in
                let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
                guard let title = lines.first else { return nil }
                var body = blocks(from: lines.dropFirst().map(String.init))
                if title.hasPrefix("Next") {
                    // the file's own note to whoever edits it is not release news
                    if case .paragraph(let first)? = body.first, first.hasPrefix("Notes for the release") {
                        body.removeFirst()
                    }
                    return ReleaseNote(title: unreleasedTitle, blocks: body)
                }
                return ReleaseNote(title: String(title), blocks: body)
            }
    }

    /// Blank lines separate paragraphs; "- " starts a list item; any other
    /// line continues whatever came before it.
    private static func blocks(from lines: [String]) -> [Block] {
        var result: [Block] = []
        var current: (isBullet: Bool, text: String)?

        func flush() {
            guard let open = current, !open.text.isEmpty else { current = nil; return }
            result.append(open.isBullet ? .bullet(open.text) : .paragraph(open.text))
            current = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flush()
                current = (true, String(trimmed.dropFirst(2)))
            } else if let open = current {
                current = (open.isBullet, open.text + " " + trimmed)
            } else {
                current = (false, trimmed)
            }
        }
        flush()
        return result
    }
}

/// An entry's body, set as prose: flowing paragraphs and a real list.
struct ReleaseNoteBody: View {
    let note: ReleaseNote

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if note.blocks.isEmpty {
                Text("No details were written for this release.")
                    .foregroundStyle(.secondary)
            }
            ForEach(note.blocks) { block in
                switch block {
                case .paragraph(let text):
                    Text(Self.styled(text))
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text("•").foregroundStyle(.tertiary)
                            .accessibilityHidden(true)  // the list structure is read from the rows
                        Text(Self.styled(text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// `code` spans and **emphasis** in the changelog render as such; text
    /// that isn't valid Markdown is shown as written.
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
