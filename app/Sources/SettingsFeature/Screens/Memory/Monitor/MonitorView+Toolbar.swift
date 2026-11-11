import SwiftUI
import AnalyzersKit

/// What the toolbar offers, in the order it matters on this screen: the lens
/// (what you are looking at) stays, Refresh and the refresh rate are
/// secondary, the Stop or Quit for the selection is the primary action, and
/// the inspector toggle closes the row.
struct MonitorToolbar: ToolbarContent {
    let model: MonitorModel
    @Binding var refreshSeconds: Int
    let selected: MonitorRow?
    let begin: (MonitorStop) -> Void
    @Binding var inspectorShown: Bool
    let refreshNow: () -> Void

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .principal) {
            Picker("Lens", selection: $model.lens) {
                ForEach(MonitorModel.Lens.allCases) { lens in
                    Label(lens.rawValue, systemImage: lens.symbol).labelStyle(.titleAndIcon).tag(lens)
                }
            }
            .pickerStyle(.segmented)
            .help("Choose what to look at")
        }
        ToolbarItem(placement: .primaryAction) {
            if let selected, let verb = selected.stopVerb {
                Button { begin(selected.stop) } label: {
                    Label(verb == "Quit" ? "Quit" : "Stop", systemImage: verb == "Quit" ? "xmark.circle" : "stop.circle")
                }
                .help("\(verb) \(selected.name)")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button("Refresh Now", systemImage: "arrow.clockwise", action: refreshNow)
                Divider()
                Picker("Refresh", selection: $refreshSeconds) {
                    Text("Every 5 Seconds").tag(5)
                    Text("Every 15 Seconds").tag(15)
                    Text("Every 60 Seconds").tag(60)
                    Text("Paused").tag(0)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh now, or choose how often")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { inspectorShown.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the details panel")
        }
    }
}
