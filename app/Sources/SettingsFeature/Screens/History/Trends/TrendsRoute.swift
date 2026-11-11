import AnalyzersKit

// The drill-down screens for the Trends pane. The pane's tiles and rows push
// `Route.history(.trends(...))`; the History group (`HistoryGroup`) turns each
// case into its screen with `trendsDestination(_:)`.

/// Push target for everything reachable from the Trends pane's tiles and
/// Repeat Offenders rows — each case carries the period the user had
/// selected so the pushed screen stays scoped to the same window.
enum TrendsRoute: Hashable, Codable, Sendable {
    case kills(TrendsModel.Period)
    case spikes(TrendsModel.Period)
    case pressure(TrendsModel.Period)
    case cpuHogs(TrendsModel.Period)
    case memoryFreed(TrendsModel.Period)
    case diskReclaimed(TrendsModel.Period)
    case reclaimableNow
    case offender(String, TrendsModel.Period)
}
