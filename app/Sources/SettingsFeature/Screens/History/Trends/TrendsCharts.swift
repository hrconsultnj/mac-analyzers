import SwiftUI
import Charts
import AnalyzersKit

/// The charts on Trends: one bar per bucket of the period (an hour for the last 24 hours, a day for the rest, see
/// `ReportPeriod.bucket`). The x axis names what a bar is (times for hours, dates for days), and pointing at a bar
/// reads out its own numbers.

private func axisFormat(_ period: ReportPeriod) -> Date.FormatStyle {
    period.bucket == .hour ? .dateTime.hour() : .dateTime.month(.abbreviated).day()
}

private func readoutTitle(_ date: Date, _ period: ReportPeriod) -> String {
    period.bucket == .hour
        ? date.formatted(.dateTime.weekday(.abbreviated).hour())
        : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
}

/// The x axis: a label every six hours, or at most seven dates whatever the length of the period.
private func xAxis(for period: ReportPeriod, count: Int) -> some AxisContent {
    let values: AxisMarkValues = period.bucket == .hour
        ? .stride(by: .hour, count: 6)
        : .stride(by: .day, count: max(1, Int((Double(count) / 7).rounded(.up))))
    return AxisMarks(values: values) { _ in
        AxisGridLine()
        AxisValueLabel(format: axisFormat(period))
    }
}

/// Guard events per bucket, stacked by what the guard did.
struct EventsChart: View {
    let buckets: [TrendBucket]
    let period: ReportPeriod
    let summary: String
    @State private var selected: Date?

    var body: some View {
        let unit = period.bucket.component
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Kills", bucket.kills))
                    .foregroundStyle(by: .value("Type", "Killed"))
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Spikes", bucket.spikes))
                    .foregroundStyle(by: .value("Type", "Spikes"))
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Other", bucket.other))
                    .foregroundStyle(by: .value("Type", "Other"))
            }
            if let bucket = bucket(at: selected) {
                RuleMark(x: .value("Selected", bucket.start, unit: unit))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(readoutTitle(bucket.start, period)).font(.caption.weight(.semibold))
                            Text("\(bucket.kills) stopped, \(bucket.spikes) \(bucket.spikes == 1 ? "spike" : "spikes"), \(bucket.other) other")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartForegroundStyleScale(["Killed": Color.red, "Spikes": Color.orange, "Other": Color.purple])
        .chartXAxis { xAxis(for: period, count: buckets.count) }
        .frame(height: 150)  // a chart needs a height; its width is the window's
        .accessibilityLabel("Bar chart of guard events per \(period.bucket == .hour ? "hour" : "day")")
        .accessibilityValue(summary)
    }

    private func bucket(at date: Date?) -> TrendBucket? {
        date.flatMap { date in buckets.last { $0.start <= date } }
    }
}

/// One number per bucket (memory freed, bytes removed), read out in the units a person reads it in.
struct ValueChart: View {
    let buckets: [TrendBucket]
    let period: ReportPeriod
    let name: String
    let color: Color
    let value: (TrendBucket) -> Double
    /// A value as text: `MemorySize` for memory, `ByteSize` for disk.
    let format: (Double) -> String
    @State private var selected: Date?

    var body: some View {
        let unit = period.bucket.component
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value(name, value(bucket)))
                    .foregroundStyle(color)
            }
            if let bucket = bucket(at: selected) {
                RuleMark(x: .value("Selected", bucket.start, unit: unit))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(readoutTitle(bucket.start, period)).font(.caption.weight(.semibold))
                            Text(value(bucket) > 0 ? format(value(bucket)) : "Nothing")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis { xAxis(for: period, count: buckets.count) }
        .chartYAxis {
            AxisMarks { mark in
                AxisGridLine()
                if let number = mark.as(Double.self) { AxisValueLabel { Text(format(number)) } }
            }
        }
        .frame(height: 150)  // a chart needs a height; its width is the window's
        .accessibilityLabel("Bar chart of \(name.lowercased()) per \(period.bucket == .hour ? "hour" : "day")")
        .accessibilityValue(format(buckets.reduce(0) { $0 + value($1) }) + " in total")
    }

    private func bucket(at date: Date?) -> TrendBucket? {
        date.flatMap { date in buckets.last { $0.start <= date } }
    }
}
