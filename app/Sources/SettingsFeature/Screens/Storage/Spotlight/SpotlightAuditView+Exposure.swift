import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Section 3: unfenced dev directories as a sized, filterable, fence-able list.
extension SpotlightAuditView {

    // MARK: - section 3: dev-directory exposure

    @ViewBuilder func exposureSection(_ run: SpotlightAuditRun) -> some View {
        Section {
            FilterChipsBar(
                chips: Filter.allCases.map { f in
                    .init(f, f.rawValue, count: count(f, run), color: chipColor(f))
                },
                selection: $filter
            )
            HStack(spacing: 6) {
                Text("Fenced \(run.fencedCount) · Unfenced \(run.unfencedCount)"
                     + (run.unfencedBulkText.map { " · \($0) out of the index" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let hint = run.applyHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Dev-directory exposure" + (run.exposureRoots.map { " (roots: \($0))" } ?? ""))
        }

        let items = filteredItems(run)
        if items.isEmpty {
            Section {
                Label("Nothing exposed — every dev directory found here is already fenced.",
                      systemImage: "checkmark.shield")
                    .foregroundStyle(.green)
            }
        } else {
            ForEach(groupedByProject(items), id: \.project) { group in
                Section("\(group.project) — \(ByteSize.format(group.total))") {
                    ForEach(group.items) { item in
                        exposureRow(item)
                    }
                }
            }
        }
    }

    /// Fenced state per row is read straight off disk, not off the parsed
    /// log line — the log's [DRY]/[FENCED] tag is only as fresh as the last
    /// script run, and a Fence/Unfence tap here doesn't re-run the script.
    /// The log still supplies the identity (path) and size; disk supplies
    /// truth about whether the marker exists right now.
    private func exposureRow(_ item: SpotlightExposureItem) -> some View {
        let exists = FileManager.default.fileExists(atPath: item.path)
        let fenced = liveStatus(item) == .fenced
        let badge = (fenced ? "FENCED" : "UNFENCED", fenced ? Color.green : Color.blue)
        return HStack(spacing: 6) {
            if exists {
                DataCard(appIcon: NSWorkspace.shared.icon(forFile: item.path),
                         title: item.cacheKind, subtitle: item.path,
                         trailing: ByteSize.format(item.sizeBytes), badge: badge)
            } else {
                DataCard(symbol: "shippingbox.fill", color: badge.1,
                         title: item.cacheKind, subtitle: item.path,
                         trailing: ByteSize.format(item.sizeBytes), badge: badge)
            }
            if exists {
                Button(fenced ? "Unfence" : "Fence") { toggleFence(item) }
                    .controlSize(.small)
                    .help(fenced
                          ? "Delete the .metadata_never_index marker — Spotlight re-indexes this directory."
                          : "Create a .metadata_never_index marker — Spotlight stops indexing this directory.")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    .accessibilityLabel("Show in Finder")
            }
        }
        // Directory is gone from disk since the audit ran — nothing to
        // fence/unfence or reveal; the row stays visible (it's still true
        // the audit found it) but reads as inert, same weight the review
        // list in Actions gives a deselected row.
        .opacity(exists ? 1 : 0.45)
    }

    private func markerPath(_ item: SpotlightExposureItem) -> String {
        (item.path as NSString).appendingPathComponent(".metadata_never_index")
    }

    func liveStatus(_ item: SpotlightExposureItem) -> SpotlightExposureItem.Status {
        // Read (not just write) fenceVersion so SwiftUI's dependency
        // tracking — driven by what a render pass actually reads, even
        // through a helper call — ties this row to the toggle below.
        _ = fenceVersion
        return FileManager.default.fileExists(atPath: markerPath(item)) ? .fenced : .dry
    }

    /// Direct FileManager marker create/delete — the app doing exactly what
    /// the script documents as the manual reversal (`rm .metadata_never_index`),
    /// no script invocation needed for a single directory. No success/failure
    /// state to track: the row re-reads the marker from disk right after, so
    /// a silent failure (e.g. permissions) just shows as "nothing changed"
    /// rather than needing its own error path.
    private func toggleFence(_ item: SpotlightExposureItem) {
        let marker = markerPath(item)
        let fm = FileManager.default
        if fm.fileExists(atPath: marker) {
            try? fm.removeItem(atPath: marker)
        } else {
            fm.createFile(atPath: marker, contents: nil)
        }
        fenceVersion += 1
    }

    private struct ExposureGroup { let project: String; let items: [SpotlightExposureItem]; let total: Int64 }

    private func groupedByProject(_ items: [SpotlightExposureItem]) -> [ExposureGroup] {
        Dictionary(grouping: items, by: \.project)
            .map { key, value in
                ExposureGroup(project: key,
                              items: value.sorted { $0.sizeBytes > $1.sizeBytes },
                              total: value.reduce(Int64(0)) { $0 + $1.sizeBytes })
            }
            .sorted { $0.total > $1.total }
    }

    /// Filtered on live status (see `exposureRow`) so a row a user just
    /// fenced/unfenced moves to the right chip immediately, without waiting
    /// on a fresh script run.
    private func filteredItems(_ run: SpotlightAuditRun) -> [SpotlightExposureItem] {
        switch filter {
        case .all: run.exposureItems
        case .unfenced: run.exposureItems.filter { liveStatus($0) == .dry }
        case .fenced: run.exposureItems.filter { liveStatus($0) == .fenced }
        }
    }

    private func count(_ f: Filter, _ run: SpotlightAuditRun) -> Int {
        switch f {
        case .all: run.exposureItems.count
        case .unfenced: run.exposureItems.filter { liveStatus($0) == .dry }.count
        case .fenced: run.exposureItems.filter { liveStatus($0) == .fenced }.count
        }
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .all: .yellow
        case .unfenced: .blue
        case .fenced: .green
        }
    }

    /// Prose the script wrote that didn't map to a specific field — shown
    /// verbatim rather than dropped, same "degrade honestly" idea as
    /// StorageCleanView's third-party raw-output block.
    func rawBlock(_ lines: [String]) -> some View {
        DisclosureGroup("Details") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
