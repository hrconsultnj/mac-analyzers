import AnalyzersKit

// The drill-down screens for the Trends pane. The pane's tiles and rows push
// `Route.history(.trends(...))`; the History group (`HistoryGroup`) turns each
// case into its screen with `trendsDestination(_:)`.

/// Push target for everything reachable from the Trends pane's tiles and
/// Repeat Offenders rows — each case carries the period the user had
/// selected so the pushed screen stays scoped to the same window.
enum TrendsRoute: Hashable, Codable, Sendable {
    case kills(ReportPeriod)
    case spikes(ReportPeriod)
    case pressure(ReportPeriod)
    case cpuHogs(ReportPeriod)
    case memoryFreed(ReportPeriod)
    case diskReclaimed(ReportPeriod)
    /// The same table with one project opened and selected (a dashboard row for it).
    case removedProject(String, ReportPeriod)
    case reclaimableNow
    case offender(String, ReportPeriod)
}
