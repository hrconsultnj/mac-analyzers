import SwiftUI
import AnalyzersKit
import UIComponents

/// One run's full detail: the run's lines parsed into sections (### markers
/// become section titles) with badge-capsule rows — a screen, not a dump.
struct RunDetailView: View {

    let route: RunRoute
    @Environment(\.dismiss) private var dismiss

    private struct RunSection: Identifiable {
        let id: Int
        let title: String?
        let lines: [String]
    }

    private var sections: [RunSection] {
        var result: [RunSection] = []
        var currentTitle: String?
        var currentLines: [String] = []
        func flush() {
            if !currentLines.isEmpty || currentTitle != nil {
                result.append(RunSection(id: result.count, title: currentTitle, lines: currentLines))
            }
            currentLines = []
        }
        for line in route.run.lines {
            if line.hasPrefix("### ") {
                flush()
                currentTitle = String(line.dropFirst(4))
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return result
    }

    var body: some View {
        PaneScaffold(symbol: route.kind.symbol, color: route.kind.tileColor,
                     title: route.kind.title,
                     caption: route.run.header) {
            Section {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("All Runs", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Text("\(route.run.itemCount) line\(route.run.itemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let badge = LogParser.badge(for: line) {
                                BadgeCapsule(text: badge.text, color: badge.color)
                            }
                            Text(LogParser.cleaned(line))
                                .font(.caption.monospaced())
                                .foregroundStyle(LogParser.badge(for: line) == nil ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    if let title = section.title {
                        Text(title).font(.callout.weight(.semibold))
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
