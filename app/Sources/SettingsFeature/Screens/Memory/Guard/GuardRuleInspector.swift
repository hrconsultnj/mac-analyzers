import SwiftUI
import AnalyzersKit

/// The selected rule or kind of Memory Guard, in words: what it does, how it is set, what protects things from it, what it
/// matches right now and what it would have done this week.
struct GuardRuleInspector: View {
    let model: GuardRulesModel
    let selected: GuardCategoryTab.Row?

    var body: some View {
        Form {
            if let selected {
                if let resolved = selected.rule { ruleSections(resolved, kind: selected.kind) } else { kindSections(selected.kind) }
            } else {
                Section { Text("Choose a kind or a rule to see what Memory Guard does about it.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func kindSections(_ kind: ProcessKind) -> some View {
        Section(kind.name) {
            Text(kind.guardMay)
            if let held = kind.leftAlone { Label(held, systemImage: "shield.lefthalf.filled").foregroundStyle(.secondary) }
            LabeledContent("Running", value: "\(model.running(kind).count)")
        }
        Section("Policy") {
            Text("This is the policy the catalog carries for this kind. The guard script does not read it yet: today it stops developer tooling by its own pattern, and nothing else.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func ruleSections(_ resolved: ResolvedRule, kind: ProcessKind) -> some View {
        let rule = resolved.rule
        Section(Names.Guard.theRule) {
            Text(rule.summary)
            LabeledContent(Names.Column.state, value: resolved.state.title)
            if case .cantRun(let why) = resolved.state { Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if let note = resolved.note { Text(note).font(.callout).foregroundStyle(.secondary) }
            if case .limit(let gb, let measure, let overFor, _) = rule.shape {
                LabeledContent("Limit", value: gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb))
                LabeledContent("Measured per", value: measure.rawValue == "unit" ? "app or service" : measure.rawValue)
                LabeledContent("For at least", value: overFor == 0 ? "no waiting" : "\(overFor / 60) min")
            }
            LabeledContent("A new process", value: "left alone for \(model.rules.plan.grace(for: kind)) s")
            LabeledContent("If it applies", value: rule.action == .stop ? "asked to stop" : rule.action == .askToQuit ? "asked to quit" : rule.action == .propose ? "proposed to you" : "you are told")
        }
        Section("Never touched") {
            Text("A live coding session and everything it started, a Connection Tool, the app in front, what is on your Never Close list and anything that runs as another account are skipped before any rule.")
                .font(.callout).foregroundStyle(.secondary)
        }
        let rows = model.outcomes.filter { $0.rule == rule.id }.prefix(8)
        Section(Names.Guard.wouldHave) {
            if rows.isEmpty { Text("Nothing in the last 7 days.").foregroundStyle(.secondary) }
            ForEach(Array(rows)) { row in
                LabeledContent {
                    Text(MemorySize.text(row.bytes)).monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.isWould ? "Would have: \(row.name)" : "Kept: \(row.name)")
                        Text(row.keptBecause ?? row.why).font(.caption).foregroundStyle(.secondary)
                        Text(row.time.formatted(.dateTime.month(.abbreviated).day().hour().minute())).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
