import SwiftUI
import AnalyzersKit
import UIComponents

/// Apps, Tools or macOS: one group row per kind (with how many are running and what they hold), and under it a row for each
/// rule that targets the kind: its state, what it says, what it matches now, what it would have done this week. One table for
/// the three tabs; a row opens the inspector.
struct GuardCategoryTab: View {
    @Bindable var model: GuardRulesModel
    let category: CensusGroup.Category

    struct Row: Identifiable {
        let id: String
        let name: String
        let detail: String
        let state: String
        let now: String
        let week: String
        let rule: ResolvedRule?
        let kind: ProcessKind
        var children: [Row]?
    }

    @State private var open = RememberedExpansion<String>(screen: "guard.kinds")

    var body: some View {
        DataScreen(title: Names.Screen.memoryGuard, subtitle: subtitle) {
            OutlineTable(Self.rows(model, category), children: \.children, selection: $model.selection, expanded: open.binding, autosave: "guard.kinds") {
                OutlineColumn("name", Names.Guard.rule, text: { $0.name })
                    .width(min: 240, ideal: 340)
                OutlineColumn("state", Names.Column.state, text: { $0.state }).width(min: 70, ideal: 90, max: 120)
                OutlineColumn("now", Names.Guard.matchingNow, text: { $0.now }).textStyle { _ in .secondary }.width(min: 90, ideal: 130)
                OutlineColumn("week", Names.Guard.thisWeek, text: { $0.week }).textStyle { _ in .secondary }.width(min: 150, ideal: 190)
            }
            .emptyContent(isLoading: model.look == nil) { EmptyView() }
        }
        .task { open.seedIfUntouched(Set(kinds.map { "kind:\($0.id)" })) }
    }

    private var kinds: [ProcessKind] { model.rules.catalog.kinds.filter { $0.category == category } }

    private var subtitle: String {
        category == .system
            ? "macOS processes can't be stopped by any app; Mac Analyzers tells you when one is using a lot."
            : "What Memory Guard does about each kind of thing here"
    }

    /// The row with this id in any of the three tabs: what the inspector shows.
    static func row(id: String, _ model: GuardRulesModel) -> Row? {
        for category in CensusGroup.Category.allCases {
            for row in rows(model, category) {
                if row.id == id { return row }
                if let found = row.children?.first(where: { $0.id == id }) { return found }
            }
        }
        return nil
    }

    static func rows(_ model: GuardRulesModel, _ category: CensusGroup.Category) -> [Row] {
        model.rules.catalog.kinds.filter { $0.category == category }.map { kind in
            let groups = model.running(kind)
            let total = groups.reduce(Int64(0)) { $0 + $1.totalBytes }
            let detail = groups.isEmpty ? "None running" : "\(groups.count) running · \(MemorySize.text(total))"
            let rules = model.rules.rules(for: kind)
            var children: [Row] = rules.map { resolved in
                let matching = model.matches(rule: resolved.id, kind: kind)
                let over = matching.count
                let counts = model.counts(rule: resolved.id, kind: kind)
                return Row(id: "rule:\(kind.id):\(resolved.id)", name: resolved.rule.summary, detail: "", state: resolved.state.title,
                           now: over == 0 ? "—" : "\(over) over now", week: weekText(counts), rule: resolved, kind: kind, children: nil)
            }
            if children.isEmpty {
                children = [Row(id: "note:\(kind.id)", name: kind.guardMay, detail: "", state: "—", now: "—", week: "—", rule: nil, kind: kind, children: nil)]
            }
            return Row(id: "kind:\(kind.id)", name: "\(kind.name) · \(detail)", detail: detail, state: "", now: "", week: "", rule: nil, kind: kind, children: children)
        }
    }

    private static func weekText(_ counts: (would: Int, kept: Int)) -> String {
        if counts.would == 0, counts.kept == 0 { return "—" }
        var parts: [String] = []
        if counts.would > 0 { parts.append("Would have acted \(counts.would)×") }
        if counts.kept > 0 { parts.append("kept \(counts.kept)×") }
        return parts.joined(separator: ", ")
    }
}
