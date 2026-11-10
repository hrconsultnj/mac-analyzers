import AnalyzersKit

// MARK: - INTEGRATION CONTRACT
//
// This file supplies the drill-down screens for the Trends pane but does NOT
// wire navigation itself — that's the caller's job. The shell must:
//   1. Own a `[TrendsRoute]` path (or fold TrendsRoute into its existing
//      route/history model) somewhere up the NavigationStack that contains
//      TrendsSettingsView. The tiles/rows in TrendsSettingsView already push
//      via `NavigationLink(value: TrendsRoute...)` — nothing else to change
//      there.
//   2. Attach `.navigationDestination(for: TrendsRoute.self) { trendsDestination($0) }`
//      on that stack.
//   3. Nothing else — `trendsDestination(_:)` is a @ViewBuilder that returns
//      the fully-built detail screen (PaneScaffold and all) for every case.

/// Push target for everything reachable from the Trends pane's tiles and
/// Repeat Offenders rows — each case carries the period the user had
/// selected so the pushed screen stays scoped to the same window.
enum TrendsRoute: Hashable {
    case kills(TrendsModel.Period)
    case spikes(TrendsModel.Period)
    case pressure(TrendsModel.Period)
    case cpuHogs(TrendsModel.Period)
    case memoryFreed(TrendsModel.Period)
    case diskReclaimed(TrendsModel.Period)
    case reclaimableNow(TrendsModel.Period)
    case offender(String, TrendsModel.Period)
}
