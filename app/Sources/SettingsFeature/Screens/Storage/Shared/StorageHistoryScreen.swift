import AnalyzersKit
import SwiftUI

/// Every time one Storage task ran — from here, from the schedule or from Terminal — as the
/// rows Activity shows, grouped by day, each opening that run's own screen.
struct StorageHistoryScreen: View {
    let kind: JobKind

    var body: some View {
        DataScreen(title: Names.job(kind), subtitle: Names.Review.history) {
            List {
                RunHistoryList(kinds: [kind], logs: kind.log.map { [$0] } ?? [],
                               emptyText: "Nothing has run here yet.")
            }
        }
    }
}
