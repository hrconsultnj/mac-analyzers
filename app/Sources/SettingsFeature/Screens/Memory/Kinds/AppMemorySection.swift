import SwiftUI
import AnalyzersKit
import UIComponents

/// App Memory's table: the Monitor's own table (the same rows, the same Quit and Stop with the same confirmations and
/// refusals) under the kind's number, with the three categories added up. Its own model reads the census while the screen
/// is open; nothing here is a second way of stopping things.
struct AppMemorySection: View {
    @Environment(Navigator.self) private var navigator
    @State private var model = MonitorModel()
    @State private var stopFlow = MonitorStopFlow()
    @State private var selection: MonitorRow.ID?
    @State private var sortOrder: [KeyPathComparator<MonitorRow>] = [KeyPathComparator(\.memoryBytes, order: .reverse)]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.pane) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Where It Is").font(.title3.weight(.semibold))
                ForEach(MonitorCategory.categories(of: model.rows).dropFirst()) { category in
                    LabeledContent {
                        Text(category.totalText).monospacedDigit()
                    } label: {
                        Label("\(category.title), \(category.groups) \(category.groups == 1 ? "group" : "groups")",
                              systemImage: category.symbol)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                }
                Text("A program's figure counts the memory macOS has compressed at its full size, as Activity Monitor's Memory column does, so these add up to more than App Memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                HStack {
                    Text("Programs").font(.title3.weight(.semibold))
                    Spacer()
                    Button(Names.MemoryKind.showInMonitor) { navigator.open(target: "monitor") }
                }
                MonitorOutline(rows: model.rows, sortOrder: $sortOrder, selection: $selection,
                               expanded: model.expansion.binding, icons: model.icons, isLoading: !model.hasLoaded,
                               empty: AnyView(EmptyView()), rowFor: { model.row($0) }, begin: stopFlow.begin,
                               open: { navigator.open(target: "monitor:select:\($0.name)") }) { row in
                    if let verb = row.stopVerb { Button("\(verb) \(row.name)…") { stopFlow.begin(row.stop) } }
                }
                .frame(height: 460)     // a table inside a scrolling form needs a height
            }
        }
        .monitorStopDialogs(stopFlow) { Task { await model.refresh(force: true) } }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
