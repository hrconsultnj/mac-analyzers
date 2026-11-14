import SwiftUI
import AnalyzersKit

/// The period control every screen with a period shares (Trends, Memory Guard): the same five choices from
/// `ReportPeriod`, one menu in the toolbar showing the period in force with its icon, and, while the data for a
/// newly chosen period is loading, a small native progress indicator beside it. The old content stays on screen
/// while that happens (no flash to empty); `periodSubtitle` says what is loading.
///
///     .toolbar { PeriodToolbar(period: $period, loading: loadingPeriod) }
///     DataScreen(title: …, subtitle: periodSubtitle(loading: loadingPeriod, "3 groups")) { … }
///
/// A screen starts a load with `.task(id: period)` so choosing again cancels the one in flight, keys its cached
/// reads by the period (`LoadCoordinator` serves a key for a few seconds: one key for every period would answer
/// the new period with the old one's rows), and sets `loadingPeriod` to the period it is loading until the result
/// arrives.
struct PeriodToolbar<Extra: View>: ToolbarContent {
    @Binding var period: ReportPeriod
    /// The period whose data is on its way, nil when nothing is loading.
    var loading: ReportPeriod?
    var placement: ToolbarItemPlacement = .automatic
    @ViewBuilder var extra: Extra

    var body: some ToolbarContent {
        // the indicator comes first, so the menu does not move when it appears
        ToolbarItem(placement: placement) {
            if loading != nil {
                ProgressView().controlSize(.small)
                    .help("Loading \(loading?.title ?? "")")
            }
        }
        ToolbarItem(placement: placement) {
            // A menu `Picker` in the toolbar draws an empty capsule (it does not show the selected title there);
            // a `Menu` shows its label, so the period in force is the label.
            Menu {
                Picker(Names.Guard.period, selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                extra
            } label: {
                Label(period.title, systemImage: "calendar")
            }
            .labelStyle(.titleAndIcon)
            .help("Choose how far back to look")
        }
    }
}

extension PeriodToolbar where Extra == EmptyView {
    init(period: Binding<ReportPeriod>, loading: ReportPeriod?, placement: ToolbarItemPlacement = .automatic) {
        self.init(period: period, loading: loading, placement: placement) { EmptyView() }
    }
}

/// A screen's subtitle while a period loads: "Loading Last 3 Days…"; otherwise `normal`.
func periodSubtitle(loading: ReportPeriod?, _ normal: String) -> String {
    loading.map { "Loading \($0.title)…" } ?? normal
}
