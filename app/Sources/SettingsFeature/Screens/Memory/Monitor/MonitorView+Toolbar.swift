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
        // the lens changes what the table measures: a filter-like choice, so a menu, not tabs
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker(Names.Monitor.lens, selection: $model.lens) {
                    ForEach(MonitorModel.Lens.allCases) { lens in
                        Label(lens.title, systemImage: lens.symbol).tag(lens)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.lens.title, systemImage: model.lens.symbol)
            }
            .help("Choose what to measure: memory, energy or disk activity")
        }
        ToolbarItem(placement: .primaryAction) {
            if let selected, let verb = selected.stopVerb {
                Button { begin(selected.stop) } label: {
                    Label(verb, systemImage: verb == Names.Stop.quit ? "xmark.circle" : "stop.circle")
                }
                .help("\(verb) \(selected.name)")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button(Names.Monitor.refreshNow, systemImage: "arrow.clockwise", action: refreshNow)
                Divider()
                Picker(Names.Monitor.refresh, selection: $refreshSeconds) {
                    Text(Names.Monitor.every5).tag(5)
                    Text(Names.Monitor.every15).tag(15)
                    Text(Names.Monitor.every60).tag(60)
                    Text(Names.Monitor.paused).tag(0)
                }
            } label: {
                Label(Names.Monitor.refresh, systemImage: "arrow.clockwise")
            }
            .help("Refresh now, or choose how often")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { inspectorShown.toggle() } label: {
                Label(Names.Monitor.inspector, systemImage: "sidebar.trailing")
            }
            .help("Show or hide the details panel")
        }
    }
}
