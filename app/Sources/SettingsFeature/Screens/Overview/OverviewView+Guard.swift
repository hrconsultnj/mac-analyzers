import SwiftUI
import AnalyzersKit
import UIComponents

/// Memory Guard: its state, how many apps it stopped today, and the last thing it did.
extension OverviewView {

    func guardBox(_ model: OverviewModel) -> some View {
        OverviewBox(title: Names.Screen.memoryGuard, symbol: "shield.lefthalf.filled") {
            if let state = model.tiles.first(where: { $0.id == "guard" }) {
                OverviewRow(action: { navigator.open(target: state.target) }) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.value)
                            Text(state.caption).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: state.symbol).foregroundStyle(color(state.tone))
                    }
                }
            }
            if let last = model.events.first {
                Divider()
                OverviewRow(action: { navigator.open(target: "log:guardLog") }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Last: \(last.title)")
                        Text("\(last.outcome) · \(last.when.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
