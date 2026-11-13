import Charts
import SwiftUI
import AnalyzersKit

/// What Activity Monitor's memory footer shows, live, on the Memory tab: the pressure of the last few minutes and
/// the figures in its words. The numbers come from `PanelMemory`, the same source as the main window's
/// "Where Your Memory Is" (`MemoryBreakdown`), so the panel, the window and Activity Monitor agree.
///
/// Sampling: every two seconds, on the main actor, ONLY while this block is on screen (the `task` below is
/// cancelled when the panel closes or another tab shows), so a closed panel costs nothing. Each sample is three
/// kernel calls, no process table. What was recorded earlier stays for the next opening (`PanelPressureTrace`).
struct MenuMemoryBlock: View {
    @State private var memory: PanelMemory?
    private let trace = PanelPressureTrace.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            graph
            if let memory { figures(memory) }
        }
        .task {
            while !Task.isCancelled {
                let taken = PanelMemory.take()
                memory = taken
                trace.record(taken?.pressurePercent)
                try? await Task.sleep(for: .seconds(PanelPressureTrace.interval))
            }
        }
    }

    /// One series, one hue, thin line over a faint fill, a fixed 0 to 100 scale, the last five minutes. A chart
    /// needs a height, so the height is fixed: drawing it is its job.
    private var graph: some View {
        let now = Date()
        return VStack(alignment: .leading, spacing: 2) {
            Chart {
                ForEach(Array(trace.runs.enumerated()), id: \.offset) { index, run in
                    ForEach(run, id: \.date) { sample in
                        AreaMark(x: .value("Time", sample.date), y: .value("Pressure", sample.percent),
                                 series: .value("Recording", index))
                            .foregroundStyle(.tint.opacity(0.15))
                        LineMark(x: .value("Time", sample.date), y: .value("Pressure", sample.percent),
                                 series: .value("Recording", index))
                            .foregroundStyle(.tint)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartXScale(domain: now.addingTimeInterval(-PanelPressureTrace.window)...now)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel().font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 56)
            .accessibilityLabel("Memory pressure over the last five minutes")
            .accessibilityValue(memory?.pressurePercent.map { "\($0) percent" } ?? "not available")
            Text("Memory pressure (higher is worse), last 5 minutes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Activity Monitor's order and spelling: two columns of a name and its figure, names at the leading edge,
    /// figures at the trailing edge of their column.
    private func figures(_ memory: PanelMemory) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                name("Physical Memory"); value(memory.physicalText)
                name("App Memory").padding(.leading, 12); value(memory.appText)
            }
            GridRow {
                name("Memory Used"); value(memory.usedText)
                name("Wired Memory").padding(.leading, 12); value(memory.wiredText)
            }
            GridRow {
                name("Cached Files"); value(memory.cachedText)
                name("Compressed").padding(.leading, 12); value(memory.compressedText)
            }
            GridRow {
                name("Swap Used"); value(memory.swapText)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func name(_ text: String) -> some View { Text(text).foregroundStyle(.secondary) }

    private func value(_ text: String) -> some View {
        Text(text).monospacedDigit().gridColumnAlignment(.trailing)
    }
}
