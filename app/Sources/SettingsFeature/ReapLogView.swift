import SwiftUI
import AnalyzersKit
import UIComponents

/// Shared pane for the two process-reap logs (memory auto-clean + reclaim):
/// the newest run parsed into status-filtered cards, with the protected-
/// session exemption surfaced as a banner instead of a buried header line.
struct ReapLogView: View {

    private enum Filter: String, CaseIterable {
        case all = "All"
        case wouldReap = "Would Reap"
        case killed = "Killed"
        case reported = "Reported"
        case exempt = "Protected"
    }

    let kind: LogKind
    @State private var run: ReapRun?
    @State private var filter: Filter = .all

    var body: some View {
        PaneScaffold(symbol: kind.symbol, color: kind.tileColor, title: kind.title,
                     caption: "Latest run, parsed — every process, its size, and what happened to it.") {
            Section {
                HStack {
                    FilterChipsBar(
                        chips: Filter.allCases.map { f in
                            .init(f, f.rawValue, count: count(f), color: chipColor(f))
                        },
                        selection: $filter
                    )
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
                        BadgeCapsule(text: run.dryRun ? "DRY RUN" : "APPLIED",
                                     color: run.dryRun ? .blue : .green)
                        Text(run.summary ?? run.header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let exempt = run.exemptNote {
                        Label(exempt, systemImage: "shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            if let run {
                if let before = run.before, let after = run.after {
                    Section("Before → After") {
                        DataCard(symbol: "arrow.down.heart", color: .teal,
                                 title: "Before", subtitle: before)
                        DataCard(symbol: "arrow.up.heart.fill", color: .green,
                                 title: "After", subtitle: after)
                    }
                }
                ForEach(run.groups) { group in
                    let visible = group.items.filter { matches($0, filter) }
                    if !visible.isEmpty || (!group.aggregates.isEmpty && filter == .all) {
                        Section(group.title) {
                            ForEach(visible) { item in
                                DataCard(symbol: symbol(for: item), color: color(for: item),
                                         title: item.friendlyName,
                                         subtitle: subtitle(for: item),
                                         trailing: item.mb.map { "\($0) MB" },
                                         badge: (badgeText(item.status), color(for: item)))
                            }
                            if filter == .all {
                                ForEach(Array(group.aggregates.enumerated()), id: \.offset) { _, agg in
                                    HStack(spacing: 6) {
                                        BadgeCapsule(text: "\(agg.count)×", color: .blue)
                                        Text(agg.label).font(.callout)
                                        Spacer()
                                        Text("\(agg.totalMB) MB total")
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if run.allItems.filter({ matches($0, filter) }).isEmpty
                    && run.groups.allSatisfy({ $0.aggregates.isEmpty }) {
                    Section {
                        Text("Nothing to show for this filter.")
                            .foregroundStyle(.secondary)
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
        .onChange(of: kind) { load() }
    }

    private func load() {
        let logKind = kind
        detachedLoad({
            LogParser.runs(for: logKind).first.map {
                ReapParser.parse(runHeader: $0.header, lines: $0.lines)
            }
        }) { run = $0 }
    }

    private func matches(_ item: ReapItem, _ f: Filter) -> Bool {
        switch f {
        case .all: true
        case .wouldReap: item.status == .dry
        case .killed: item.status == .killed || item.status == .quit
        case .reported: item.status == .reported || item.status == .gone
        case .exempt: item.status == .exempt
        }
    }

    private func count(_ f: Filter) -> Int {
        run.map { $0.allItems.filter { matches($0, f) }.count } ?? 0
    }

    private func chipColor(_ f: Filter) -> Color {
        switch f {
        case .all: kind.tileColor
        case .wouldReap: .blue
        case .killed: .red
        case .reported: .orange
        case .exempt: .green
        }
    }

    private func subtitle(for item: ReapItem) -> String {
        var parts: [String] = []
        if let pid = item.pid { parts.append("pid \(pid)") }
        if item.friendlyName != item.description {
            parts.append(String(item.description.prefix(70)))
        }
        return parts.joined(separator: " · ")
    }

    private func symbol(for item: ReapItem) -> String {
        item.status == .exempt ? "shield.fill" : "hammer.fill"
    }

    private func color(for item: ReapItem) -> Color {
        switch item.status {
        case .dry: .blue
        case .killed, .quit: .red
        case .reported: .orange
        case .gone, .skip: .gray
        case .exempt: .green
        }
    }

    private func badgeText(_ status: ReapItem.Status) -> String {
        status == .exempt ? "PROTECTED" : status.rawValue
    }
}
