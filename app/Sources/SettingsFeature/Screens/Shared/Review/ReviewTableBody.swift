import AppKit
import AnalyzersKit
import SwiftUI
import UIComponents

/// The drawing of the review table, and only that: this one file is what changes when grouped
/// tables move onto the app's shared outline table, so nothing else in the review knows how rows
/// are laid out. It is given the tree to draw and, unless the review is read-only, the session to
/// tick through.
///
/// The ticks here are a VIEW of the session and a way to change it, nothing more: Apply, the bar,
/// the confirmation and what is sent all read `ReviewSession` / `ReviewSelection`, never this table
/// (`OutlineTicks.set` reaches the session one main turn after a click, by design).
struct ReviewTableBody: View {
    let nodes: [ReviewNode]
    @Binding var sortOrder: [KeyPathComparator<ReviewNode>]
    /// nil for a review that is only read: no tick column, no boxes.
    let session: ReviewSession?
    /// Which groups are open on this screen, kept across window close and relaunch.
    let expansion: RememberedExpansion<String>
    /// The screen's key: column widths, order and hidden columns are kept per screen too.
    let screen: String
    /// What the first column and the value column are called when the review is not about files and
    /// sizes: a column is named for what it holds, and a review of things with no size and no value
    /// has no value column at all.
    var nameTitle: String = Names.Column.name
    var valueTitle: String?
    /// A screen's items for a row; nil leaves the table without a menu.
    var rowMenu: ReviewRowMenu?
    /// The review's own rows for a set of line ids (a group's or the fold's id matches none).
    var rowsFor: @MainActor (Set<String>) -> [ReviewRow] = { _ in [] }

    @State private var selection: Set<String> = []

    /// A few groups holding a screenful of rows: open. Many groups, or thousands of rows (a Downloads
    /// review): closed, so the screen opens on its groups and their totals, never one long list.
    /// Decided once, for a screen nobody has opened or closed a group on yet; the fold of empty rows
    /// is never seeded open.
    private static let openByDefault = 6
    private static let openRowLimit = 200

    var body: some View {
        var table = OutlineTable(nodes, children: \.children, selection: $selection, sortOrder: $sortOrder,
                                 expanded: expansion.binding, autosave: screen) {
            OutlineColumn("name", nameTitle, sortUsing: KeyPathComparator(\ReviewNode.sortName)) { node in
                ReviewNameCell(node: node)
            }
            .help { $0.detail ?? $0.title }
            // the title and, under it, what the row is: two lines when there is something to say
            .lines { $0.detail == nil ? 1 : 2 }
            .typeSelect { $0.title }
            if let columnTitle = Self.valueColumnTitle(nodes, valueTitle: valueTitle) {
                OutlineColumn("size", columnTitle,
                              text: { $0.bytes.map(ByteSize.format) ?? $0.valueText ?? "" },
                              sortUsing: KeyPathComparator(\ReviewNode.sortBytes))
                    .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                    // a size is a short number: a column wide enough for "3.20 GB", not half the table
                    .width(min: 72, ideal: 96, max: 140)
            }
        }
        // rows the cleanup leaves alone are drawn dimmed; they can still be selected, so the
        // reason beside them can be read
        .rowEnabled { !$0.isKept }
        if let rowMenu {
            table = table.contextMenu { ids in rowMenu.items(rowsFor(ids)) }
        }
        return Group {
            if let session {
                table.ticks(OutlineTicks(
                    state: { Self.tickState($0, session: session) },
                    set: { node, ticked in session.setTicked(node.rowIDs, ticked) },
                    label: { Self.tickLabel($0) }))
            } else {
                table
            }
        }
        .onChange(of: nodes.count, initial: true) { seed() }
    }

    /// "Size" when the rows have sizes, the caller's title when they carry another value (a time), and no
    /// column when they carry neither.
    static func valueColumnTitle(_ nodes: [ReviewNode], valueTitle: String?) -> String? {
        func any(_ keep: (ReviewNode) -> Bool, in list: [ReviewNode]) -> Bool {
            list.contains { keep($0) || any(keep, in: $0.children ?? []) }
        }
        if any({ $0.bytes != nil }, in: nodes) { return Names.Column.size }
        if any({ $0.valueText != nil }, in: nodes) { return valueTitle ?? Names.Column.size }
        return nil
    }

    /// A row's tick: on or off for one thing the review can choose, on, mixed or off for a group
    /// (computed over its choosable members), and disabled when nothing in it can be chosen: off for
    /// a row the cleanup leaves alone, on for one the apply acts on without a tick.
    static func tickState(_ node: ReviewNode, session: ReviewSession) -> OutlineTickState {
        if node.rowIDs.isEmpty {
            let reason = node.isGroup ? "Nothing in it can be chosen" : (node.detail ?? node.title)
            // on for a row the apply acts on, and for a group made only of those
            let acts = node.acts || (node.children.map { !$0.isEmpty && $0.allSatisfy(\.acts) } ?? false)
            return .unavailable(reason: reason, isOn: acts)
        }
        let ticked = node.rowIDs.reduce(0) { $0 + (session.isTicked($1) ? 1 : 0) }
        if ticked == 0 { return .off }
        return ticked == node.rowIDs.count ? .on : .mixed
    }

    /// What VoiceOver says for a box, by what the box means: a row that can be chosen is "Include X"; one the
    /// cleanup leaves alone says so, and its reason follows as the help; one the apply acts on without a tick
    /// says what will happen ("Opera: Will Be Asked to Quit"), not an invitation to include it.
    static func tickLabel(_ node: ReviewNode) -> String {
        if !node.rowIDs.isEmpty { return "Include \(node.title)" }
        if node.acts { return "\(node.title): \(node.detail ?? "")" }
        if let kids = node.children, !kids.isEmpty, kids.allSatisfy(\.acts) { return "\(node.title): the apply acts on these without a tick" }
        return "Not chosen: \(node.title)"
    }

    private func seed() {
        guard !nodes.isEmpty else { return }
        let groups = nodes.filter { $0.isGroup && $0.id != ReviewNode.foldID }
        let rows = groups.reduce(0) { $0 + ($1.children?.count ?? 0) }
        let openThem = groups.count <= Self.openByDefault && rows <= Self.openRowLimit
        // a group whose rows are all kept starts closed: there is nothing in it the person can do
        expansion.seedIfUntouched(openThem ? Set(groups.filter { !$0.isKept }.map(\.id)) : [])
    }
}

/// The name cell: the icon, the name and what is under it. The tick sits in the outline's first
/// column, beside the arrow that opens a group, so it is not drawn here.
struct ReviewNameCell: View {
    let node: ReviewNode
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                // one line each: the row is two lines tall (`lines`), so a longer text is cut, not wrapped
                Text(node.title).lineLimit(1)
                if let detail = node.detail {
                    Text(detail).font(.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(isEnabled ? Color.secondary : Color(nsColor: .disabledControlTextColor))
                }
            }
        } icon: {
            if let path = node.iconPath {
                // a file's own icon is a picture of a fixed size, not a control
                Image(nsImage: ReviewIcons.image(path)).resizable().scaledToFit().frame(width: 20, height: 20)
            } else if node.isGroup {
                Image(systemName: "folder")
            }
        }
    }
}

/// The open-groups memory of each screen the review table is used on: one per key, kept for as long
/// as the table is on screen.
@MainActor
final class ReviewExpansions {
    private var made: [String: RememberedExpansion<String>] = [:]

    func expansion(for key: String) -> RememberedExpansion<String> {
        if let existing = made[key] { return existing }
        let created = RememberedExpansion<String>(screen: key)
        made[key] = created
        return created
    }
}

/// Finder icons by path: a table redraws a cell on every tick and scroll, and
/// asking the workspace each time is slow with thousands of rows.
@MainActor
enum ReviewIcons {
    private static var cache: [String: NSImage] = [:]
    static func image(_ path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
