import SwiftUI
import AnalyzersKit
import UIComponents

/// The Logs landing screen — General-pane style: one chevron row per log,
/// pushing the log's own pane (native back button in the toolbar).
struct LogsHomeView: View {
    var body: some View {
        PaneScaffold(symbol: "doc.text.magnifyingglass", color: .gray,
                     title: "Logs",
                     caption: "Every receipt the suite writes — pick a log to read it newest-first.") {
            Section {
                ForEach(LogKind.allCases) { kind in
                    NavigationLink(value: kind) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title)
                                if let date = kind.url.flatMap(AnalyzersPaths.modificationDate) {
                                    Text("Updated \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            IconTile(symbol: kind.symbol, color: kind.tileColor, side: 20)
                        }
                    }
                }
            }
        }
    }
}
