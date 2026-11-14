import SwiftUI
import AnalyzersKit
import UIComponents

/// One kind of memory on its own screen, opened from a row of the Monitor's "Where Your Memory Is" block: the number, what
/// it is, how it moved over the last minutes, and what is behind it where the system lets an app read that. Only App Memory
/// has actions (the same Quit and Stop as Monitor); the rest say plainly what cannot be read and why.
///
/// The text comes from `MemoryKindReport` (so `agent-runner --probe-memory-kinds` prints what is read here), the history
/// from the one `MemoryTrend`, which samples only while a screen like this is open.
struct MemoryKindScreen: View {
    let kind: MemoryKind
    @Environment(Navigator.self) private var navigator
    @State private var trend = MemoryTrend.shared

    var body: some View {
        let report = MemoryKindReport.make(kind, samples: trend.samples)
        DataScreen(title: kind.title, subtitle: report.map(subtitle)) {
            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.pane) {
                        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                            Text(report.headline)
                                .font(.system(size: 40, weight: .semibold)).monospacedDigit()
                            Text(report.caption).foregroundStyle(.secondary)
                            Text(kind.whatItIs).font(.callout).foregroundStyle(.secondary).padding(.top, Tokens.Space.s)
                        }
                        block(Names.MemoryKind.overTime) {
                            ForEach(report.charts) { TrendChart(chart: $0) }
                            if !report.pressure.isEmpty { PressureStrip(bands: report.pressure) }
                        }
                        VStack(spacing: 0) {
                            ForEach(report.facts, id: \.label) { fact in
                                HStack {
                                    Text(fact.label)
                                    Spacer(minLength: Tokens.Space.xxl)
                                    Text(fact.value).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .padding(.vertical, Tokens.Space.s)
                                Divider()
                            }
                        }
                        switch kind {
                        case .app: AppMemorySection()
                        case .compressed: CompressedHoldersSection()
                        default: EmptyView()
                        }
                        VStack(alignment: .leading, spacing: Tokens.Space.s) {
                            ForEach(report.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .padding()          // the screen's own margin: the content runs the width of the window
                }
            } else {
                LoadingState("Reading memory…")
            }
        }
        .onAppear { trend.begin() }
        .onDisappear { trend.end() }
    }

    /// A titled block: the title, then its content, with room between the parts.
    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func subtitle(_ report: MemoryKindReport) -> String {
        guard let since = report.since else { return "" }
        return "Since \(since.formatted(date: .omitted, time: .shortened))"
    }
}
