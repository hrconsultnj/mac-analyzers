import SwiftUI
import Charts
import AnalyzersKit
import UIComponents

/// One chart of the memory screens: lines on ONE axis, 2 pt thick, a dashed line for a second series of the same kind (so
/// identity is never colour alone), a legend whenever there is more than one series, and a crosshair with the values at the
/// pointer. The colour of a line is the colour of its row in the Monitor's block: identity follows the entity.
struct TrendChart: View {
    let chart: MemoryKindReport.Chart
    @State private var hovered: Date?

    private func tint(_ kind: MemoryKind) -> Color {
        switch kind {
        case .app: .blue
        case .wired: .indigo
        case .compressed: .purple
        case .cached: .teal
        case .free: .gray
        case .swap: .brown
        }
    }

    private func text(_ value: Double) -> String {
        switch chart.unit {
        case .bytes: MemorySize.text(Int64(value), .axis)
        case .bytesPerSecond: MemoryKindReport.rateText(value)
        }
    }

    private func axisText(_ value: Double) -> String {
        chart.unit == .bytes ? MemoryKindReport.axisBytesText(value) : MemoryKindReport.rateText(value)
    }

    /// The vertical range: the data with a little room, never below zero. A flat line (swap that is not moving) still gets a
    /// scale to sit on, and a rate starts at zero.
    private var yDomain: ClosedRange<Double> {
        let values = chart.series.flatMap { $0.points.map(\.value) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if chart.unit == .bytesPerSecond { return 0...max(high * 1.15, 100 * 1_024) }
        let pad = max((high - low) * 0.2, high * 0.02, 16 * 1_048_576)
        return max(0, low - pad)...(high + pad)
    }

    private var span: TimeInterval {
        let dates = chart.series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max() else { return 0 }
        return last.timeIntervalSince(first)
    }

    /// The point of a series nearest to a moment.
    private func nearest(_ series: MemoryKindReport.Series, to date: Date) -> (date: Date, value: Double)? {
        series.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(chart.title).font(.headline)
            Chart {
                ForEach(chart.series) { series in
                    ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Time", point.date), y: .value(series.name, point.value),
                                 series: .value("Series", series.name))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: series.dashed ? [5, 3] : []))
                            .foregroundStyle(tint(series.tint))
                    }
                }
                if let hovered {
                    RuleMark(x: .value("Time", hovered))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hovered, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                                ForEach(chart.series) { series in
                                    if let point = nearest(series, to: hovered) {
                                        Text("\(series.name): \(text(point.value))").font(.caption).monospacedDigit()
                                    }
                                }
                            }
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let number = value.as(Double.self) { Text(axisText(number)).foregroundStyle(.secondary) } }
                }
            }
            .chartXAxis {
                let marks = timeAxisStride(span: span)
                AxisMarks(values: timeAxisValues(span: span)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { timeLabel(value, marks.showsSeconds) }
                }
            }
            .chartXSelection(value: $hovered)
            .frame(height: 170)     // a chart needs a height; its width is the window's
            .accessibilityLabel(chart.title)
            .accessibilityValue(summary)
            if chart.series.count > 1 {
                HStack(spacing: Tokens.Space.xl) {
                    ForEach(chart.series) { series in
                        HStack(spacing: 6) {
                            Capsule().fill(tint(series.tint)).frame(width: 18, height: 2)
                                .overlay { if series.dashed { Rectangle().fill(.background).frame(width: 3, height: 3) } }
                                .accessibilityHidden(true)
                            Text(series.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// For VoiceOver and for anyone who cannot read the lines: the newest, lowest and highest value of each series.
    private var summary: String {
        chart.series.compactMap { series in
            guard let last = series.points.last?.value, let low = series.points.map(\.value).min(),
                  let high = series.points.map(\.value).max() else { return nil }
            return "\(series.name): now \(text(last)), lowest \(text(low)), highest \(text(high))"
        }.joined(separator: ". ")
    }
}
