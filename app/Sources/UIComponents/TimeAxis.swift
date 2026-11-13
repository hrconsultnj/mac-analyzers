import SwiftUI
import Charts

/// About five time labels however long the history is: every 15 s while it is young, then every minute, then every 5 minutes
/// (the automatic choice printed a label per second and cut the last one off).
public func timeAxisStride(span: TimeInterval) -> (component: Calendar.Component, count: Int, showsSeconds: Bool) {
    switch span {
    case ..<90: (.second, 15, true)
    case ..<420: (.minute, 1, false)
    case ..<1_500: (.minute, 5, false)
    default: (.minute, 10, false)
    }
}

/// The tick positions for a time axis: automatic while the history is only seconds old (a fixed step may land no tick in it).
public func timeAxisValues(span: TimeInterval) -> AxisMarkValues {
    if span < 25 { return .automatic(desiredCount: 4) }
    let marks = timeAxisStride(span: span)
    return .stride(by: marks.component, count: marks.count)
}

/// A time tick's label in the secondary text colour (a label given a format takes the accent colour, which reads as a link).
@ViewBuilder public func timeLabel(_ value: AxisValue, _ showsSeconds: Bool) -> some View {
    if let date = value.as(Date.self) {
        Text(date, format: showsSeconds ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
            .foregroundStyle(.secondary)
    }
}
