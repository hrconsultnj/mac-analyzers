import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The Monitor tab's table: the app's one table for rows that open, on the system outline view. A group opens
/// with the outline's own triangle; a row with nothing inside keeps the triangle's space, so names line up and the
/// column never jumps. Columns: the name (icon, name and one short phrase), the size, and Quit, Stop or a lock.
/// Double-click or Return opens Monitor on that app or tool.
struct MenuMonitorTable: View {
    let nodes: [MenuPanelModel.Node]
    let scope: MonitorScope
    let flow: PanelStopFlow
    let reload: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var selection: Set<String> = []
    /// Which groups are open, per tab, kept across window close and relaunch.
    @State private var expansions = PanelExpansions()

    /// A table needs a height, and the panel's is fixed: it shows this many rows and scrolls inside.
    private static let height: CGFloat = 290

    var body: some View {
        let opened = expansions.expansion(for: "panel.monitor.\(scope.rawValue)")
        OutlineTable(nodes, children: \.children, selection: $selection, expanded: opened.binding,
                     autosave: "panel.monitor") {
            OutlineColumn("name", Names.Column.name) { node in MenuNodeName(node: node) }
                .help { $0.breakdown ?? $0.name }
                .typeSelect { $0.name }
            OutlineColumn("size", Names.Column.size, text: \.sizeText)
                .alignment(.trailing).monospacedDigits().textStyle { _ in .secondary }
                .width(min: 60, ideal: 66, max: 80)
            OutlineColumn("action", "") { node in MenuNodeAction(node: node, flow: flow) }
                .alignment(.trailing).hideable(false)
                .width(min: 56, ideal: 60, max: 64)
        }
        .columnHeaders(.hidden)
        .alternatingRows(false)
        .contextMenu({ ids in
            if let node = node(for: ids) {
                Button("Open in \(Names.Screen.monitor)") { open(node) }
            }
        }, primaryAction: { ids in
            if let node = node(for: ids) { open(node) }
        })
        .emptyContent(isLoading: false) {
            Text("Nothing here").foregroundStyle(.secondary)
        }
        .frame(height: Self.height)
    }

    private func node(for ids: Set<String>) -> MenuPanelModel.Node? {
        guard let id = ids.first else { return nil }
        for node in nodes {
            if node.id == id { return node }
            if let member = node.children?.first(where: { $0.id == id }) { return member }
        }
        return nil
    }

    private func open(_ node: MenuPanelModel.Node) {
        SettingsOpener.open(target: MemoryStop.monitorLink(forGroup: node.groupName))
    }
}

/// The open-groups memory of each tab: one per key, for as long as the panel's view is alive.
@MainActor
final class PanelExpansions {
    private var made: [String: RememberedExpansion<String>] = [:]

    func expansion(for key: String) -> RememberedExpansion<String> {
        if let existing = made[key] { return existing }
        let created = RememberedExpansion<String>(screen: key)
        made[key] = created
        return created
    }
}

/// A row's name: its app's icon (or its category's symbol), the name, and one short phrase. A member has an icon
/// of its own at a smaller size (an app's parts take the app's, a tool's programs the terminal's), so its name sits
/// one indentation level in from its parent's name.
private struct MenuNodeName: View {
    let node: MenuPanelModel.Node

    var body: some View {
        HStack(spacing: 6) {
            icon.frame(width: node.group == nil ? 12 : 16, height: node.group == nil ? 12 : 16).accessibilityHidden(true)
            Text(node.name)
            if let detail = node.detail {
                Text(detail).foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if let source = node.group ?? node.owner, node.category == .apps, let image = GroupIcon.image(for: source) {
            Image(nsImage: image).resizable()
        } else {
            IconTile(symbol: node.category.symbol, color: node.category == .tools ? .blue : .gray,
                     side: node.group == nil ? 12 : 16)
        }
    }
}

/// Quit for an app, Stop for a program, a lock (reason on hover) for what cannot be stopped from here; nothing for a member.
private struct MenuNodeAction: View {
    let node: MenuPanelModel.Node
    let flow: PanelStopFlow

    var body: some View {
        if let group = node.group {
            switch PanelStop.offer(for: group) {
            case .quit:
                Button("Quit") { flow.begin(group) }
                    .controlSize(.small)
                    .disabled(flow.working || flow.asking != nil)
                    .help("Quit \(node.name) and its helpers, like ⌘Q — save prompts still appear")
            case .stop:
                Button("Stop") { flow.begin(group) }
                    .controlSize(.small)
                    .disabled(flow.working || flow.asking != nil)
                    .help("Ask \(node.name) to stop; nothing is forced")
            case .locked(let reason):
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .help(reason)
                    .accessibilityLabel("Cannot be stopped from here")
                    .accessibilityHint(reason)
            }
        }
    }
}
