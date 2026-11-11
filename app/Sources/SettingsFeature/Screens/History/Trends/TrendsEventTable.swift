import SwiftUI
import AnalyzersKit
import UIComponents

/// One row of the event table: a day (drawn as a section header) holding its
/// events, or one event. Days are data, not recovered from titles.
struct TrendsEventNode: Identifiable {
    let id: String
    let row: OverviewModel.EventRow?
    let title: String
    let when: Date
    let children: [TrendsEventNode]?

    /// Events grouped by day, each day with its events.
    static func days(_ rows: [OverviewModel.EventRow]) -> [TrendsEventNode] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.when) }
        return byDay.map { day, events in
            TrendsEventNode(
                id: "day:\(Int(day.timeIntervalSince1970))", row: nil,
                title: ActivityDay(day: day, rows: []).title(now: Date()), when: day,
                children: events.map { TrendsEventNode(id: $0.id, row: $0, title: $0.title, when: $0.when, children: nil) })
        }
    }
}

/// Guard events as a sortable table grouped by day: when, which app, what
/// happened, how much memory. The same rows the Overview and the menu-bar panel list.
struct TrendsEventTable: View {
    let rows: [OverviewModel.EventRow]
    let emptyTitle: String
    @Environment(Navigator.self) private var navigator
    @State private var days: [TrendsEventNode] = []
    @State private var selection: Set<String> = []
    /// Days are always open when they appear; the person can close one while looking.
    @State private var open: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\TrendsEventNode.when, order: .reverse)]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle",
                                   description: Text("Nothing was recorded in this period."))
        } else {
            OutlineTable(shown, children: \.children, selection: $selection, sortOrder: $sortOrder,
                         expanded: $open, autosave: "trends.events") {
                OutlineColumn("when", Names.Column.when, text: { $0.row.map { time($0.when) } ?? "" },
                              sortUsing: KeyPathComparator(\TrendsEventNode.when))
                    .monospacedDigits()
                    .width(min: 80, ideal: 100, max: 140)
                OutlineColumn("name", Names.Column.name,
                              sortUsing: KeyPathComparator(\TrendsEventNode.title, comparator: .localizedStandard)) { node in
                    if let event = node.row {
                        Label(event.title, systemImage: event.event.symbol).foregroundStyle(event.event.tint)
                    }
                }
                .width(min: 150, ideal: 220)
                OutlineColumn("outcome", Names.Column.whatHappened, text: { $0.row?.outcome ?? "" })
                    .width(min: 200, ideal: 320)
                OutlineColumn("memory", Names.Column.memory, text: { $0.row.map { $0.event.residentText ?? "—" } ?? "" })
                    .textStyle { _ in .secondary }
                    .alignment(.trailing).monospacedDigits()
                    .width(min: 70, ideal: 80, max: 120)
            }
            .sectionHeader { node in
                node.row == nil ? OutlineSectionHeader(title: node.title, summary: count(node)) : nil
            }
            .contextMenu({ _ in
                Button("Open \(Names.Screen.memoryGuard)") { navigator.open(target: "log:guardLog") }
            }, primaryAction: { _ in
                navigator.open(target: "log:guardLog")   // double-click or Return
            })
            .onChange(of: rows.count, initial: true) {
                days = TrendsEventNode.days(rows)
                open.formUnion(days.map(\.id))
            }
        }
    }

    /// Days in the order of the "When" column's direction, events inside each by the chosen column.
    private var shown: [TrendsEventNode] {
        let oldestFirst = sortOrder.first.map {
            ($0.keyPath as AnyKeyPath) == (\TrendsEventNode.when as AnyKeyPath) && $0.order == .forward
        } ?? false
        return days.sorted { oldestFirst ? $0.when < $1.when : $0.when > $1.when }.map { day in
            TrendsEventNode(id: day.id, row: nil, title: day.title, when: day.when,
                            children: day.children?.sorted(using: sortOrder))
        }
    }

    private func count(_ day: TrendsEventNode) -> String {
        let n = day.children?.count ?? 0
        return "\(n) \(n == 1 ? "event" : "events")"
    }

    private func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
}
