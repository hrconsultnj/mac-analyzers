import SwiftUI
import AnalyzersKit
import UIComponents

/// The Logs landing screen — General-pane style: one chevron row per log.
/// Rows route through the SAME pane selection the sidebar uses (via the
/// internal deep-link channel) — never a pushed copy of the log inside this
/// stack, which is what left the sidebar highlight stuck on "Logs".
struct LogsHomeView: View {
    var body: some View {
        PaneScaffold(symbol: "doc.text.magnifyingglass", color: .gray,
                     title: "Logs",
                     caption: "Every receipt the suite writes — pick a log to read it newest-first.") {
            Section {
                ForEach(LogKind.allCases) { kind in
                    Button {
                        NotificationCenter.default.post(
                            name: NotifyChannel.openPaneInternal, object: nil,
                            userInfo: ["target": "log:\(kind.rawValue)"])
                    } label: {
                        HStack {
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
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
