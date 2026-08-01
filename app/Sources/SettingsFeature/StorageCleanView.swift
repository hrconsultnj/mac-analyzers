import SwiftUI
import AnalyzersKit
import UIComponents

/// Storage auto-clean pane: the numbers ARE the story — projects sorted by
/// reclaimable size, third-party passthrough honestly collapsed as raw.
struct StorageCleanView: View {

    private enum Filter: String, CaseIterable {
        case all = "All"
        case caches = "Build Caches"
        case nodeModules = "node_modules"
        case raw = "Tool Output"
    }

    let kind: LogKind
    @State private var run: StorageCleanRun?
    @State private var filter: Filter = .all

    /// One pane, two storage-shaped logs: the auto-clean (zones + raw
    /// passthrough) and the janitor (Downloads/Screenshots by folder).
    init(kind: LogKind = .storageClean) {
        self.kind = kind
    }

    private var caption: String {
        kind == .janitor
            ? "Latest tidy, parsed — what moved (or would move) to the Trash, by folder."
            : "Latest run, parsed — biggest reclaimable space first."
    }

    var body: some View {
        PaneScaffold(symbol: kind.symbol, color: kind.tileColor, title: kind.title,
                     caption: caption) {
            Section {
                HStack {
                    if kind == .storageClean {
                        FilterChipsBar(
                            chips: Filter.allCases.map { f in
                                .init(f, chipLabel(f), count: 0, color: chipColor(f))
                            },
                            selection: $filter
                        )
                    }
                    Spacer(minLength: 8)
                    if let url = kind.url {
                        Button("Open in TextEdit") { GuardControl.openLog(url) }
                    }
                    Button {
                        load()
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh")
                }
                if let run {
                    HStack(spacing: 6) {
                        if kind == .storageClean {
                            BadgeCapsule(text: run.mode.uppercased(), color: .indigo)
                        }
                        BadgeCapsule(text: run.dryRun ? "DRY RUN" : "APPLIED",
                                     color: run.dryRun ? .blue : .green)
                        Text(run.summary ?? run.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let free = run.freeSpaceAfter {
                            Text(free).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let run {
                if filter == .all || filter == .caches || filter == .nodeModules {
                    let wanted: [StoragePathItem.Section] =
                        filter == .caches ? [.buildCaches]
                        : filter == .nodeModules ? [.nodeModules]
                        : [.buildCaches, .nodeModules]
                    let byProject = Dictionary(grouping: run.items.filter { wanted.contains($0.section) },
                                               by: \.project)
                        .map { (project: $0.key, items: $0.value,
                                total: $0.value.reduce(Int64(0)) { $0 + $1.sizeBytes }) }
                        .sorted { $0.total > $1.total }

                    if byProject.isEmpty {
                        Section {
                            Text("Nothing to reclaim — all caches are fresh or none configured.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(byProject, id: \.project) { group in
                        Section {
                            DisclosureGroup {
                                ForEach(group.items.sorted { $0.sizeBytes > $1.sizeBytes }) { item in
                                    DataCard(symbol: cacheSymbol(item.cacheKind),
                                             color: statusColor(item.status),
                                             title: item.cacheKind,
                                             subtitle: item.path,
                                             trailing: ByteSize.format(item.sizeBytes),
                                             badge: (item.status.rawValue, statusColor(item.status)))
                                }
                            } label: {
                                HStack {
                                    IconTile(symbol: "folder.fill", color: .indigo)
                                    Text(group.project).font(.callout.weight(.medium))
                                    Spacer()
                                    Text(ByteSize.format(group.total))
                                        .font(.callout.monospacedDigit().weight(.semibold))
                                }
                            }
                        }
                    }
                    if let note = run.activeRepoNote, filter != .caches {
                        Section {
                            Label(note, systemImage: "shield.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                if filter == .all || filter == .raw {
                    if !run.packageManagerRaw.isEmpty {
                        Section("Package-Manager Caches") {
                            rawBlock(run.packageManagerRaw)
                        }
                    }
                    if !run.dockerRaw.isEmpty {
                        Section("Docker Prune") {
                            rawBlock(run.dockerRaw)
                        }
                    }
                }
                if let tm = run.tmNote, filter == .all {
                    Section("Time Machine Snapshots") {
                        DataCard(symbol: "clock.arrow.circlepath", color: .teal,
                                 title: "Local snapshots", subtitle: tm)
                    }
                }
            } else {
                Section {
                    Text("No runs logged yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Third-party CLI output — the one place a collapsed monospaced block is
    /// honest (this app doesn't own that text's structure).
    private func rawBlock(_ lines: [String]) -> some View {
        DisclosureGroup("Raw output (\(lines.count) lines)") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.prefix(40).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func load() {
        let logKind = kind
        detachedLoad({
            LogParser.runs(for: logKind).first.map {
                StorageCleanParser.parse(runHeader: $0.header, lines: $0.lines)
            }
        }) { run = $0 }
    }

    private func chipLabel(_ f: Filter) -> String {
        guard let run else { return f.rawValue }
        switch f {
        case .all: return f.rawValue
        case .caches:
            let total = run.items.filter { $0.section == .buildCaches }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }
            return total > 0 ? "\(f.rawValue) · \(ByteSize.format(total))" : f.rawValue
        case .nodeModules:
            let total = run.items.filter { $0.section == .nodeModules }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }
            return total > 0 ? "\(f.rawValue) · \(ByteSize.format(total))" : f.rawValue
        case .raw:
            return f.rawValue
        }
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .all: .indigo
        case .caches: .blue
        case .nodeModules: .brown
        case .raw: .gray
        }
    }

    private func cacheSymbol(_ kind: String) -> String {
        switch kind {
        case ".next": "n.square.fill"
        case ".turbo": "wind"
        case "node_modules": "shippingbox.fill"
        case "dist", "build": "hammer.fill"
        default: "folder.fill"
        }
    }

    private func statusColor(_ status: StoragePathItem.Status) -> Color {
        switch status {
        case .dry: .blue
        case .deleted: .green
        case .trashed: .orange
        case .restored: .gray
        case .failed: .red
        }
    }
}
