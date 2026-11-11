import AppKit
import AnalyzersKit
import SwiftUI

/// The drawing of the review table, and only that: this one file is what changes
/// when grouped tables move onto the app's shared outline table, so nothing else in
/// the review knows how rows are laid out. It is given the tree to draw and, unless
/// the review is read-only, the session to tick through.
struct ReviewTableBody: View {
    let nodes: [ReviewNode]
    @Binding var sortOrder: [KeyPathComparator<ReviewNode>]
    /// nil for a review that is only read: no tick column, no boxes.
    let session: ReviewSession?

    var body: some View {
        Table(nodes, children: \.children, sortOrder: $sortOrder) {
            TableColumn(Names.Review.nameColumn, value: \.sortName) { node in nameCell(node) }
            TableColumn(Names.Review.sizeColumn, value: \.sortBytes) { node in
                Text(node.bytes.map(ByteSize.format) ?? node.valueText ?? "").monospacedDigit().foregroundStyle(.secondary)
            }
            // a size is a short number: a column wide enough for "3.20 GB", not half the table
            .width(min: 72, ideal: 96, max: 140)
        }
    }

    /// A tick (mixed when only some of a group is ticked; disabled for a row the cleanup
    /// leaves alone), the icon, the name and what is under it. The tick sits in the first
    /// column, beside the arrow that opens a group.
    private func nameCell(_ node: ReviewNode) -> some View {
        HStack {
            if let session {
                tick(node, session: session)
            }
            Label {
                VStack(alignment: .leading) {
                    Text(node.title)
                    if let detail = node.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
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
        .help(node.detail ?? node.title)
    }

    @ViewBuilder private func tick(_ node: ReviewNode, session: ReviewSession) -> some View {
        if node.rowIDs.isEmpty {
            // nothing here can be chosen: the box is shown dimmed, off for a row the cleanup leaves
            // alone and on for one it acts on without a tick
            Toggle("Not chosen: \(node.title)", isOn: .constant(node.acts)).labelsHidden().disabled(true)
        } else {
            let ticks = Binding<[ReviewTick]>(
                get: { node.rowIDs.map { ReviewTick(id: $0, isOn: session.isTicked($0)) } },
                set: { for tick in $0 { session.setTicked(tick.id, tick.isOn) } })
            Toggle(sources: ticks, isOn: \.isOn) { Text("Include \(node.title)") }
                .labelsHidden()
        }
    }
}

/// One tick of a review, in the shape `Toggle(sources:isOn:)` reads so a group's
/// checkbox shows the mixed state when only some of its members are ticked.
private struct ReviewTick: Identifiable {
    let id: String
    var isOn: Bool
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
