import SwiftUI
import AppKit
import AnalyzersKit
import UIComponents

/// Finder-style capacity bar: used fill over a track, color escalating with
/// fullness. (A per-category segmented bar like the system Storage pane
/// needs a full-disk scan — the storage analyzer's report has that detail;
/// this bar answers the at-a-glance question.)
struct CapacityBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 7)
    }

    private var color: Color {
        fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .blue
    }
}

/// Two-line event row: friendly what-happened on top, raw identity +
/// mechanics + time underneath. Click opens the guard log.
struct EventRow: View {
    let event: GuardEvent

    var body: some View {
        Button {
            GuardControl.openLog(AnalyzersPaths.guardLog)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.caption)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title)
                        .font(.callout)
                        .foregroundStyle(color)
                        .lineLimit(1)
                    Text(subtitleWithTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .help(event.raw)
    }

    private var subtitleWithTime: String {
        let time = event.date.formatted(.dateTime.hour().minute())
        return event.subtitle.isEmpty ? time : "\(event.subtitle) · \(time)"
    }

    private var symbol: String {
        switch event.kind {
        case .killed: "xmark.octagon.fill"
        case .spike: "arrow.up.right"
        case .warning: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch event.kind {
        case .killed: .red
        case .spike, .warning: .orange
        }
    }
}
