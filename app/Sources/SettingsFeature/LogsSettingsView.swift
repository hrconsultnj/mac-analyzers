import SwiftUI
import AnalyzersKit
import UIComponents

/// One log's pane: a list of RUNS (newest first) — each run pushes its own
/// parsed detail screen, the same nesting pattern as the Logs landing page.
struct LogsSettingsView: View {

    let kind: LogKind
    @State private var runs: [LogRun] = []

    var body: some View {
        // structured panes for the logs with dedicated parsers; the generic
        // run list remains for the rest (survey phases 3-4)
        switch kind {
        case .guardLog: GuardLogView()
        case .loginItems: LoginItemsView()
        default: genericRunList
        }
    }

    private var genericRunList: some View {
        PaneScaffold(symbol: kind.symbol, color: kind.tileColor, title: kind.title,
                     caption: "Newest runs first — pick one for the full detail. The file itself is never modified.") {
            Section {
                HStack {
                    Button {
                        // explicit intent: land on the Logs screen AND move
                        // the sidebar highlight there (signal, not inference)
                        NotificationCenter.default.post(name: logsHomeSignal, object: nil)
                    } label: {
                        Label("All Logs", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    if let url = kind.url {
                        Text(mtime(url)).font(.caption).foregroundStyle(.secondary)
                        Button("Open in TextEdit") { GuardControl.openLog(url) }
                        Button {
                            load()
                        } label: { Image(systemName: "arrow.clockwise") }
                            .help("Refresh")
                    }
                }
            }
            if runs.isEmpty {
                Section {
                    Text("Nothing logged yet — this log appears after its first run.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(runs) { run in
                    NavigationLink(value: RunRoute(kind: kind, run: run)) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                if let badge = run.summary.flatMap(LogParser.badge(for:)) {
                                    BadgeCapsule(text: badge.text, color: badge.color)
                                }
                                Text(run.header)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                if let summary = run.summary {
                                    Text(LogParser.cleaned(summary))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text("\(run.itemCount) line\(run.itemCount == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: load)
        .onChange(of: kind) { load() }
    }

    private func load() {
        runs = LogParser.runs(for: kind)
    }

    private func mtime(_ url: URL) -> String {
        AnalyzersPaths.modificationDate(of: url)
            .map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? ""
    }
}
