import SwiftUI
import AnalyzersKit
import UIComponents

/// The Logs landing screen. Category pills narrow the list; a selected
/// category switches from compact rows to BIG cards (latest-run summary,
/// larger tiles) — the review-first reading of the same documents. Rows
/// route through the SAME pane selection the sidebar uses.
struct LogsHomeView: View {

    enum Category: String, CaseIterable {
        case all = "All"
        case memory = "Memory"
        case storage = "Storage"
        case downloads = "Downloads"
        case network = "Network"
        case system = "System"
    }

    /// (mtime, latest-run summary) per log — parsed off-main on appear.
    struct LogFact: Sendable {
        let date: Date?
        let summary: String?
    }

    @State private var category: Category = .all
    @State private var facts: [String: LogFact] = [:]

    private func bucket(_ kind: LogKind) -> Category {
        switch kind {
        case .guardLog, .memoryClean, .reclaim: .memory
        case .storageClean: .storage
        case .janitor: .downloads
        case .network: .network
        case .loginItems, .forensics: .system
        }
    }

    private var visibleKinds: [LogKind] {
        category == .all ? LogKind.allCases
                         : LogKind.allCases.filter { bucket($0) == category }
    }

    var body: some View {
        PaneScaffold(symbol: "doc.text.magnifyingglass", color: .gray,
                     title: "Logs",
                     caption: "Every receipt the suite writes — pick a log to read it newest-first.") {
            Section {
                FilterChipsBar(
                    chips: Category.allCases.map { cat in
                        .init(cat, cat.rawValue,
                              count: cat == .all ? LogKind.allCases.count
                                  : LogKind.allCases.filter { bucket($0) == cat }.count,
                              color: chipColor(cat))
                    },
                    selection: $category
                )
            }
            Section {
                ForEach(visibleKinds) { kind in
                    if category == .all {
                        compactRow(kind)
                    } else {
                        bigCard(kind)
                    }
                }
            }
        }
        .onAppear(perform: loadFacts)
    }

    // MARK: - rows

    private func compactRow(_ kind: LogKind) -> some View {
        Button {
            open(kind)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                        if let date = facts[kind.rawValue]?.date {
                            Text("Updated \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    IconTile(symbol: kind.symbol, color: kind.tileColor, side: 20)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The review card: bigger tile, two lines, the latest run's own words.
    private func bigCard(_ kind: LogKind) -> some View {
        Button {
            open(kind)
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: kind.symbol, color: kind.tileColor, side: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                    if let summary = facts[kind.rawValue]?.summary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let date = facts[kind.rawValue]?.date {
                        Text("Updated \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - plumbing

    private func open(_ kind: LogKind) {
        NotificationCenter.default.post(
            name: NotifyChannel.openPaneInternal, object: nil,
            userInfo: ["target": "log:\(kind.rawValue)"])
    }

    private func chipColor(_ category: Category) -> Color {
        switch category {
        case .all: .gray
        case .memory: .blue
        case .storage: .indigo
        case .downloads: .orange
        case .network: .purple
        case .system: .brown
        }
    }

    private func loadFacts() {
        detachedLoad({
            var result: [String: LogFact] = [:]
            for kind in LogKind.allCases {
                let date = kind.url.flatMap(AnalyzersPaths.modificationDate)
                let summary = LogParser.runs(for: kind).first?.summary
                    .map(LogParser.cleaned)
                result[kind.rawValue] = LogFact(date: date, summary: summary)
            }
            return result
        }) { facts = $0 }
    }
}
