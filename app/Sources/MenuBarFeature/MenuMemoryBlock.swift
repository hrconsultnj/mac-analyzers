import SwiftUI
import AnalyzersKit
import UIComponents

/// What Activity Monitor's memory footer shows, live, on the Memory tab: the pressure of the last five minutes and
/// the figures in its words. Both come from the app's ONE sampler (`MemoryTrend`) and its one function for the
/// figures (`MemoryBreakdown`), the same the main window's memory screens read, so the panel, the window and
/// Activity Monitor agree.
///
/// Sampling: `MemoryTrend` samples every two seconds only while some screen has begun, and this block begins when it
/// appears and ends when it goes (the panel closing or another tab), so a closed panel costs nothing.
struct MenuMemoryBlock: View {
    private let trend = MemoryTrend.shared
    /// How much history the strip shows.
    private static let seconds: TimeInterval = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            strip
            if let sample = trend.latest { figures(sample) }
        }
        .onAppear { trend.begin() }
        .onDisappear { trend.end() }
    }

    /// Activity Monitor's pressure graph: bar height is how much pressure there is, colour is the state, the legend names
    /// the states. The shared `PressureStrip`, the same one the memory screens draw.
    private var strip: some View {
        VStack(alignment: .leading, spacing: 2) {
            PressureStrip(bands: trend.window(seconds: Self.seconds).map {
                MemoryKindReport.Band(date: $0.date, level: $0.pressureLevel, percent: $0.pressurePercent)
            }, title: nil, showsTimeAxis: false, plotHeight: 44)
            Text("Memory pressure, last 5 minutes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Activity Monitor's order and spelling, in the `figure` size style: two columns of a name and its figure, names
    /// at the leading edge, figures at the trailing edge of their column.
    private func figures(_ sample: MemorySample) -> some View {
        let b = sample.breakdown
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                name("Physical Memory"); value(b.totalBytes)
                name("App Memory").padding(.leading, 12); value(b.appBytes)
            }
            GridRow {
                name("Memory Used"); value(b.usedBytes)
                name("Wired Memory").padding(.leading, 12); value(b.wiredBytes)
            }
            GridRow {
                name("Cached Files"); value(b.cachedBytes)
                name("Compressed").padding(.leading, 12); value(b.compressedBytes)
            }
            GridRow {
                name("Swap Used"); value(sample.swapUsedBytes)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func name(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }

    private func value(_ bytes: Int64?) -> some View {
        Text(bytes.map { ByteSize.text($0, .figure) } ?? "—").monospacedDigit().gridColumnAlignment(.trailing)
    }
}
