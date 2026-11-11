import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// The audited rows, grouped by where they live, with filter chips and Finder reveal.
extension TempSpaceView {

    // MARK: - rows, grouped by where they live

    @ViewBuilder func itemSections(_ run: TempCleanRun) -> some View {
        Section {
            FilterChipsBar(
                chips: Filter.allCases.map { f in
                    .init(f, f.rawValue, count: matching(f, run).count, color: chipColor(f))
                },
                selection: $filter
            )
        }
        let visible = matching(filter, run)
        if visible.isEmpty {
            Section {
                Label(emptyText, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(run.sections, id: \.self) { section in
                let rows = visible.filter { $0.section == section }.sorted { $0.sizeBytes > $1.sizeBytes }
                if !rows.isEmpty {
                    Section("\(section) — \(ByteSize.format(rows.reduce(0) { $0 + $1.sizeBytes }))") {
                        let showAll = expanded.contains(section) || rows.count <= Self.collapsedRows
                        ForEach(showAll ? rows : Array(rows.prefix(Self.collapsedRows))) { item in
                            itemRow(item)
                        }
                        if rows.count > Self.collapsedRows {
                            Button(showAll ? "Show Fewer" : "Show All \(rows.count)") {
                                if showAll { expanded.remove(section) } else { expanded.insert(section) }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        switch filter {
        case .ready: "Nothing is ready to clear — everything here is recent, in use, or not yours."
        case .leftAlone: "Nothing was left alone."
        case .sized: "No history or managed areas found."
        case .all: "Nothing found."
        }
    }

    private func itemRow(_ item: TempItem) -> some View {
        let exists = !item.isGroup && FileManager.default.fileExists(atPath: item.path)
        return HStack(spacing: 6) {
            Group {
                if exists {
                    DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                             title: item.displayName, subtitle: subtitle(item),
                             trailing: ByteSize.format(item.sizeBytes), badge: badge(item))
                } else {
                    DataCard(symbol: item.isGroup ? "square.stack.3d.up" : "doc",
                             color: badge(item).1,
                             title: item.displayName, subtitle: subtitle(item),
                             trailing: ByteSize.format(item.sizeBytes), badge: badge(item))
                }
            }
            .help(item.path)
            if item.isGroup {
                revealButton(item.parentPath, help: "Show the folder in Finder")
            } else if exists {
                revealButton(item.path, help: "Show in Finder")
            }
        }
        // acted-on or vanished rows stay listed (it is still what happened)
        // but read as inert, the weight Actions gives a deselected row
        .opacity(item.wasActedOn || (!item.isGroup && !exists) ? 0.55 : 1)
    }

    private func subtitle(_ item: TempItem) -> String {
        var parts: [String] = []
        if item.isGroup { parts.append("\(item.count) items") }
        if !item.ejects.isEmpty {
            parts.append("ejects \(item.ejects.count) disk image\(item.ejects.count == 1 ? "" : "s") first")
        }
        if let reason = item.reason { parts.append(reason) }
        return parts.isEmpty ? item.path : parts.joined(separator: " · ")
    }

    private func badge(_ item: TempItem) -> (String, Color) {
        switch item.status {
        case .dry: ("Ready", .blue)
        case .trashed: ("Trashed", .orange)
        case .deleted: ("Deleted", .red)
        case .failed: ("Failed", .red)
        case .skip: ("Unticked", .gray)
        case .recent: ("Recent", .teal)
        case .inUse: ("In Use", .green)
        case .protected: ("Protected", .green)
        case .notYours: ("Not Yours", .gray)
        case .keep: ("Your Keep List", .gray)
        case .system: ("System", .gray)
        case .history: ("History", .purple)
        case .kept: ("Kept", .gray)
        case .managed: ("Managed", .gray)
        }
    }

    private func matching(_ f: Filter, _ run: TempCleanRun) -> [TempItem] {
        switch f {
        case .ready:
            run.items.filter { $0.isReady || $0.wasActedOn || $0.status == .failed || $0.status == .skip }
        case .leftAlone:
            run.items.filter {
                [.recent, .inUse, .protected, .notYours, .keep, .system].contains($0.status)
            }
        case .sized: run.items.filter(\.isSizedOnly)
        case .all: run.items
        }
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .ready: .blue
        case .leftAlone: .green
        case .sized: .purple
        case .all: .mint
        }
    }

    func revealButton(_ path: String, help: String) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: { Image(systemName: "magnifyingglass.circle") }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
    }
}
