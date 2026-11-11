import SwiftUI
import AnalyzersKit
import UIComponents

/// Shared row formatting for the Trends drill-downs.
func eventTime(_ event: GuardEvent) -> String {
    event.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}

func eventSubtitleWithTime(_ event: GuardEvent) -> String {
    event.subtitle.isEmpty ? eventTime(event) : "\(event.subtitle) · \(eventTime(event))"
}

/// "6144 MB" style numbers formatted the same way the rest of Trends does —
/// GB once it's over a gig, plain MB below that.
func formatMB(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
}
