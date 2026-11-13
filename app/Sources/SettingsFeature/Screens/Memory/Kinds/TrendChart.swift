import SwiftUI
import Charts
import AnalyzersKit
import UIComponents

/// One chart of the memory screens: lines on ONE axis, 2 pt thick, a dashed line for a second series of the same kind (so
/// identity is never colour alone), a legend whenever there is more than one series, and a crosshair with the values at the
/// pointer. The colour of a line is the colour of its row in the Monitor's block: identity follows the entity.
/// About five time labels however long the history is: every 15 s while it is young, then every minute, then every 5 minutes
/// (the automatic choice printed a label per second and cut the last one off).
func timeAxisStride(span: TimeInterval) -> (component: Calendar.Component, count: Int, showsSeconds: Bool) {
    switch span {
    case ..<90: (.second, 15, true)
    case ..<420: (.minute, 1, false)
    case ..<1_500: (.minute, 5, false)
    default: (.minute, 10, false)
    }
}

/// The tick positions for a time axis: automatic while the history is only seconds old (a fixed step may land no tick in it).
func timeAxisValues(span: TimeInterval) -> AxisMarkValues {
    if span < 25 { return .automatic(desiredCount: 4) }
    let marks = timeAxisStride(span: span)
    return .stride(by: marks.component, count: marks.count)
}

/// A time tick's label in the secondary text colour (a label given a format takes the accent colour, which reads as a link).
@ViewBuilder func timeLabel(_ value: AxisValue, _ showsSeconds: Bool) -> some View {
    if let date = value.as(Date.self) {
        Text(date, format: showsSeconds ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
            .foregroundStyle(.secondary)
    }
}

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

/// The pressure level over time as a strip, with its legend: each state has a word and a symbol, never colour alone.
struct PressureStrip: View {
    let bands: [MemoryKindReport.Band]

    /// Consecutive samples at one level drawn as one stretch, so a calm hour is one bar and not a bar per sample.
    private var runs: [(from: Date, to: Date, level: Int)] {
        var found: [(from: Date, to: Date, level: Int)] = []
        for (index, band) in bands.enumerated() {
            let end = index + 1 < bands.count ? bands[index + 1].date : band.date.addingTimeInterval(2)
            if let last = found.last, last.level == band.level { found[found.count - 1].to = end }
            else { found.append((band.date, end, band.level)) }
        }
        return found
    }

    private var spanSeconds: TimeInterval {
        guard let first = bands.first?.date, let last = bands.last?.date else { return 0 }
        return last.timeIntervalSince(first)
    }

    private func look(_ level: Int) -> (word: String, symbol: String, color: Color) {
        switch level {
        case ..<2: ("Normal", "checkmark.circle.fill", .green)
        case 2..<4: ("Warning", "exclamationmark.triangle.fill", .yellow)
        default: ("Critical", "exclamationmark.octagon.fill", .red)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Memory Pressure").font(.headline)
            Chart {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    BarMark(xStart: .value("From", run.from), xEnd: .value("To", run.to), y: .value("Pressure", "level"))
                        .foregroundStyle(look(run.level).color)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                let marks = timeAxisStride(span: spanSeconds)
                AxisMarks(values: timeAxisValues(span: spanSeconds)) { value in
                    AxisValueLabel { timeLabel(value, marks.showsSeconds) }
                }
            }
            .chartPlotStyle { plot in plot.frame(height: 22) }     // the strip itself; the labels sit under it
            .frame(height: 52)
            .accessibilityLabel("Memory pressure over time")
            .accessibilityValue(bands.last.map { "now \(look($0.level).word)" } ?? "")
            HStack(spacing: Tokens.Space.xl) {
                ForEach([1, 2, 4], id: \.self) { level in
                    Label {
                        Text(look(level).word).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: look(level).symbol).foregroundStyle(look(level).color)
                    }
                    .font(.caption)
                }
            }
        }
    }
}
