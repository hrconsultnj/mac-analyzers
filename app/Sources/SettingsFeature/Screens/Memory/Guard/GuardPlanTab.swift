import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// When Memory Runs Out: the plan in one sentence, its steps in the order they are tried (each with what it would pick right
/// now), what nothing may touch right now, and the two lists the person keeps.
struct GuardPlanTab: View {
    let model: GuardRulesModel
    @State private var adding: Names.GuardList?
    @State private var addedName = ""

    var body: some View {
        DataScreen(title: Names.Screen.memoryGuard, subtitle: subtitle) {
            Form {
                Section {
                    Text(GuardRule.ladderSentence(model.rules.steps.filter { $0.state != .off }.map(\.rule)))
                    Text("Memory Guard is only watching in this version: a step marked Watching records what it would have done and stops nothing. "
                         + "The dev-tooling steps marked Acting are the ones the guard script already carries out.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let notice = model.notice { Section { Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
                Section(Names.Guard.steps) {
                    ForEach(model.rules.steps) { step in stepRow(step) }
                }
                Section {
                    ForEach(protectedNow, id: \.name) { item in
                        LabeledContent { Text(item.why).foregroundStyle(.secondary) } label: { Label(item.name, systemImage: item.symbol) }
                    }
                    if protectedNow.isEmpty { Text("Nothing running is protected by name right now.").foregroundStyle(.secondary) }
                } header: { Text(Names.Guard.protectedNow) } footer: {
                    Text("What a live coding session started, a Connection Tool, the app in front and what you listed below is never stopped, whatever a rule says.")
                }
                list(.mayQuit, Names.Guard.mayQuitList, "Apps you list here may be asked to quit, as ⌘Q does, only when memory has run out. None is listed.",
                     choices: model.groups.filter { $0.category == .apps }.map(\.name))
                list(.neverClose, Names.Guard.neverCloseList, "Memory Guard and the cleanups that sweep developer tools and leftover helpers never touch what is listed here: a name of an app or program, or the full path of a program. Quitting apps by name in Memory Cleanup is your own choice and is not checked against this list.",
                     choices: model.groups.filter { $0.category != .system }.map(\.name))
            }
            .formStyle(.grouped)
        }
        .toolbar {
            ToolbarItem {
                Button(Names.Monitor.refresh, systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .help("Look at what is running again")
            }
        }
    }

    private var subtitle: String {
        if model.loading && model.look == nil { return "Looking at what is running…" }
        let pressure = LiveStats.memoryPressure().label
        return "Memory pressure: \(pressure)"
    }

    private func stepRow(_ step: ResolvedRule) -> some View {
        let pick = model.evaluation?.picks.first { $0.rule.id == step.id }
        let counts = model.counts(rule: step.id)
        return LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(step.state.title).font(.caption.weight(.semibold)).foregroundStyle(color(step.state))
                if counts.would + counts.kept > 0 {
                    Text("Would have acted \(counts.would) \(counts.would == 1 ? "time" : "times") this week").font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(step.rule.summary)
                Text(wouldPick(pick, step)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if step.state != .acting {
                Button(step.state == .off ? "Turn On" : "Turn Off") { model.setOff(step.id, step.state != .off) }
            }
        }
    }

    private func wouldPick(_ pick: StepPick?, _ step: ResolvedRule) -> String {
        if case .cantRun(let why) = step.state { return "Can't run: \(why)." }
        if step.state == .off { return "Off." }
        if let note = pick?.note { return note }
        if let match = pick?.match { return "Would pick now: \(match.unit.name), \(MemorySize.text(match.unit.bytes)) (\(match.kind.name))." }
        return "Would pick now: nothing."
    }

    private func color(_ state: RuleState) -> Color {
        switch state {
        case .acting: .green
        case .watching: .blue
        case .off: .secondary
        case .cantRun: .orange
        }
    }

    /// What nothing may touch right now, from what is running.
    private var protectedNow: [(name: String, why: String, symbol: String)] {
        var found: [(String, String, String)] = []
        let rules = model.rules
        for group in model.groups {
            if rules.protected.kinds.contains(group.kind.id) {
                found.append((group.name, group.kind == model.rules.catalog.kind(id: "tools.codingAgents") ? "a live coding session" : group.kind.name, "lock.fill"))
            } else if rules.protected.names.contains(group.name.lowercased()) {
                found.append((group.name, "never touched", "lock.fill"))
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication?.localizedName { found.append((front, "the app in front", "macwindow")) }
        for name in rules.local.neverClose { found.append((name, "on your Never Close list", "hand.raised.fill")) }
        var seen = Set<String>()
        return found.filter { seen.insert($0.0.lowercased() + $0.1).inserted }.prefix(24).map { $0 }
    }

    @ViewBuilder private func list(_ kind: Names.GuardList, _ title: String, _ footer: String, choices: [String]) -> some View {
        let entries = kind == .mayQuit ? model.rules.local.mayQuit : model.rules.local.neverClose
        Section {
            ForEach(entries, id: \.self) { name in
                LabeledContent(name) {
                    Button("Remove", systemImage: "minus.circle") { model.remove(kind, name) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            Menu("Add…", systemImage: "plus") {
                ForEach(Array(Set(choices)).sorted().filter { !entries.contains($0) }.prefix(40), id: \.self) { name in
                    Button(name) { model.add(kind, name) }
                }
            }
        } header: { Text(title) } footer: { Text(footer) }
    }
}
