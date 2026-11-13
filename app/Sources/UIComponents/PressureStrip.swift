import AnalyzersKit
import Charts
import SwiftUI

/// Memory pressure over time, shaped like Activity Monitor's graph: the HEIGHT of each bar is how much pressure
/// there is (0 to 100) and its COLOUR is the state the kernel reports (green normal, orange warning, red critical).
/// The legend names each state with its word and symbol, so the colour is never the only thing that says it.
/// One component for the memory screens and the menu-bar panel.
public struct PressureStrip: View {
    let bands: [MemoryKindReport.Band]
    let title: String?
    let showsTimeAxis: Bool
    let plotHeight: CGFloat

    public init(bands: [MemoryKindReport.Band], title: String? = "Memory Pressure", showsTimeAxis: Bool = true,
                plotHeight: CGFloat = 56) {
        self.bands = bands
        self.title = title
        self.showsTimeAxis = showsTimeAxis
        self.plotHeight = plotHeight
    }

    private var spanSeconds: TimeInterval {
        guard let first = bands.first?.date, let last = bands.last?.date else { return 0 }
        return last.timeIntervalSince(first)
    }

    private static func look(_ level: Int) -> (word: String, symbol: String, color: Color) {
        switch level {
        case ..<2: ("Normal", "checkmark.circle.fill", .green)
        case 2..<4: ("Warning", "exclamationmark.triangle.fill", .orange)
        default: ("Critical", "exclamationmark.octagon.fill", .red)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.headline) }
            Chart {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    // a bar runs to the next sample, so a calm stretch is a solid block and not a comb
                    let end = index + 1 < bands.count ? bands[index + 1].date : band.date.addingTimeInterval(2)
                    RectangleMark(xStart: .value("From", band.date), xEnd: .value("To", end),
                                  yStart: .value("Base", 0), yEnd: .value("Pressure", band.percent))
                        .foregroundStyle(Self.look(band.level).color)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                if showsTimeAxis {
                    let marks = timeAxisStride(span: spanSeconds)
                    AxisMarks(values: timeAxisValues(span: spanSeconds)) { value in
                        AxisValueLabel { timeLabel(value, marks.showsSeconds) }
                    }
                }
            }
            .chartPlotStyle { plot in plot.frame(height: plotHeight) }     // the graph itself; a chart needs a height
            .frame(height: plotHeight + (showsTimeAxis ? 30 : 0))
            .accessibilityLabel("Memory pressure over time")
            .accessibilityValue(bands.last.map { "now \(Self.look($0.level).word), \($0.percent) percent" } ?? "")
            HStack(spacing: 12) {
                ForEach([1, 2, 4], id: \.self) { level in
                    Label {
                        Text(Self.look(level).word).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: Self.look(level).symbol).foregroundStyle(Self.look(level).color)
                    }
                    .font(.caption)
                }
            }
        }
    }
}
