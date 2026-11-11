import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Review of Temp & Agents: rows grouped by where things live, the disk-image
/// eject notes and the left-alone count.
extension ActionsSettingsView {

    @ViewBuilder var tempReviewSections: some View {
        if let run = tempRun {
            if phase == .review, !run.readyItems.isEmpty {
                Section { selectionBar }
            }
            let ejecting = run.readyItems.filter { !$0.ejects.isEmpty && !deselected.contains($0.path) }
            if phase == .review, !ejecting.isEmpty {
                Section {
                    ForEach(ejecting) { item in
                        DataCard(symbol: "opticaldiscdrive", color: .purple,
                                 title: "\(item.displayName) backs mounted disk images",
                                 subtitle: "Applying ejects them first (never forced): "
                                     + item.ejects.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "),
                                 badge: ("Ejects First", .purple))
                    }
                }
            }
            let shown = run.items.filter { $0.isReady || $0.wasActedOn || $0.status == .failed }
            ForEach(run.sections, id: \.self) { section in
                let rows = shown.filter { $0.section == section }.sorted {
                    sortByName
                        ? $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                        : $0.sizeBytes > $1.sizeBytes
                }
                if !rows.isEmpty {
                    Section("\(section) — \(ByteSize.format(rows.reduce(0) { $0 + $1.sizeBytes }))") {
                        ForEach(rows) { item in
                            selectable(item.isReady ? item.path : nil, name: item.displayName) {
                                tempRow(item)
                            }
                        }
                    }
                }
            }
            let leftAlone = run.items.filter {
                [.recent, .inUse, .protected, .notYours].contains($0.status)
            }.reduce(0) { $0 + $1.count }
            if leftAlone > 0 {
                Section {
                    Label("\(leftAlone) item\(leftAlone == 1 ? "" : "s") left alone this run — recent, in use, a live session, or not yours. Logs › Temp & Agents says why for each.",
                          systemImage: "shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func tempRow(_ item: TempItem) -> some View {
        let exists = !item.isGroup && FileManager.default.fileExists(atPath: item.path)
        var bits: [String] = []
        if item.isGroup { bits.append("\(item.count) items") }
        if let reason = item.reason { bits.append(reason) }
        let subtitle = bits.isEmpty ? item.path : bits.joined(separator: " · ")
        let badge: (String, Color) = switch item.status {
        case .trashed: ("Trashed", .orange)
        case .deleted: ("Deleted", .red)
        case .failed: ("Failed", .red)
        default: recoverableNow ? ("Would Trash", .blue) : ("Would Delete", .red)
        }
        return HStack(spacing: 6) {
            Group {
                if exists {
                    DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                             title: item.displayName, subtitle: subtitle,
                             trailing: ByteSize.format(item.sizeBytes), badge: badge)
                } else {
                    DataCard(symbol: item.isGroup ? "square.stack.3d.up" : "doc", color: badge.1,
                             title: item.displayName, subtitle: subtitle,
                             trailing: ByteSize.format(item.sizeBytes), badge: badge)
                }
            }
            .help(item.path)
            if exists || item.isGroup {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: item.isGroup ? item.parentPath : item.path)])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }
        }
    }
}
