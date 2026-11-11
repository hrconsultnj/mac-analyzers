import SwiftUI
import AnalyzersKit
import UIComponents

/// Schedules: the two scheduled cleans, when each runs and how the last one
/// ended, from the schedule itself and the log. Each opens the Schedule settings.
extension OverviewView {

    var schedulesBox: some View {
        OverviewBox(title: Names.Screen.schedule, symbol: "calendar.badge.clock") {
            scheduleRow("Daily Clean", label: GuardControl.storageCleanLabel, last: store.storageDailySummary)
            scheduleRow("Deep Clean", label: GuardControl.storageDeepLabel, last: store.storageDeepSummary)
            Text("Memory Guard runs all the time, checking every 15 seconds.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scheduleRow(_ title: String, label: String, last: String?) -> some View {
        // an interval schedule ("every 86400 seconds since it was loaded") has no clock time
        let when = ScheduleKit.describe(label)
        return OverviewValueRow(label: title, value: when.contains(" at ") || !when.hasPrefix("Every") ? when : when + ", no fixed time",
                         action: { navigator.open(target: "schedule") },
                         caption: last.map { "Last run: \($0)" } ?? "Has not run yet.")
    }
}
