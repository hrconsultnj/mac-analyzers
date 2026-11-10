import SwiftUI
import AnalyzersKit
import UIComponents

/// One run's full detail: the run's lines parsed into sections (### markers
/// become section titles) with badge-capsule rows — a screen, not a dump.
struct RunDetailView: View {

    let route: RunReference
    /// Found again from the reference: a route holds an identifier, not the run.
    @State private var run: LogRun?
    @State private var notFound = false

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
        for line in run?.lines ?? [] {
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
        PaneScaffold(symbol: route.log.symbol, color: route.log.tileColor,
                     title: route.log.title,
                     caption: route.header) {
            Section {
                HStack {
                    Spacer()
                    Text(run.map { "\($0.itemCount) line\($0.itemCount == 1 ? "" : "s")" }
                         ?? (notFound ? "This run is no longer in the log" : ""))
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
        .task {
            let reference = route
            await awaitLoad({ reference.resolve(in: LogParser.runs(for: reference.log)) },
                            key: "run:\(reference.log.rawValue):\(reference.index):\(reference.header)") {
                run = $0
                notFound = ($0 == nil)
            }
        }
    }
}
