import AnalyzersKit
import SwiftUI
import UIComponents

/// Step 1: three things Sparehold does, each with this Mac's own numbers.
struct WelcomeIntroStep: View {
    let numbers: WelcomeNumbers?

    var body: some View {
        Form {
            if let numbers {
                Section {
                    row("memorychip", "Memory",
                        "\(ByteSize.text(numbers.memoryTotal, .headline)), \(ByteSize.text(numbers.memoryUsed, .headline)) in use now",
                        "It is watched all the time, and an app that takes too much is flagged.")
                    row("internaldrive", "Storage",
                        "\(ByteSize.text(numbers.diskTotal, .headline)) disk, \(ByteSize.text(numbers.diskUsed, .headline)) used, \(ByteSize.text(numbers.diskFree, .headline)) free",
                        "Caches, old downloads and leftovers are listed for you to review before a cleanup you start is applied. The background cleanups you turn on next run by themselves: \(Names.Group.settings) › \(Names.Screen.schedule) changes when, and \(Names.Screen.setup) › \(Names.Screen.turnOff) switches them all off.")
                    row("person.crop.circle.badge.questionmark", "Start-up",
                        numbers.startupItems.map { "\($0) things start by themselves" } ?? "Everything that starts by itself, listed",
                        "Login items, launch agents and background helpers, with what is left behind by apps you removed.")
                }
            } else {
                LoadingState("Reading this Mac…")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ symbol: String, _ title: String, _ figure: String, _ sentence: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: symbol).imageScale(.large).frame(width: 28).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title).font(.callout.weight(.medium))
                Text(figure).font(.callout)
                Text(sentence).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Tokens.Space.xs)
    }
}

/// Step 2: the background jobs, each with its schedule and whether it is loaded now, and the login item.
struct WelcomeBackgroundStep: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        Form {
            Section("Background Jobs") {
                ForEach(model.items.filter { $0.id.hasPrefix("job.") }) { item in
                    SetupItemRow(item: item, working: false, busy: true, session: nil, confirmed: false,
                                 onAction: {}, onCloseGuidance: {}, showsAction: false)
                }
            }
            Section {
                Toggle(isOn: $model.openAtLogin) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text("Open Sparehold when you log in")
                        Text(loginEvidence).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("If you choose Not Now, nothing runs in the background until you turn it on in Setup.")
            }
        }
        .formStyle(.grouped)
    }

    private var loginEvidence: String { model.item("login")?.evidence ?? "" }
}

/// Step 3: the plan of "When Memory Runs Out" as the Memory Guard Plan tab shows it: the steps in the order they are tried, each
/// with what it would pick on this Mac right now and whether it is Watching or Acting, and what is protected right now.
struct WelcomeGuardStep: View {
    let preview: GuardPlanPreview.Plan?

    var body: some View {
        if let preview {
            Form {
                Section {
                    Text(preview.ladder)
                    Text(preview.note).font(.callout).foregroundStyle(.secondary)
                }
                Section(Names.Guard.steps) {
                    ForEach(preview.steps) { step in
                        LabeledContent {
                            Text(step.state.title).font(.caption.weight(.semibold)).foregroundStyle(color(step.state))
                        } label: {
                            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                                Text(step.summary)
                                Text(step.wouldPick).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    ForEach(preview.protected, id: \.self) { item in
                        LabeledContent { Text(item.why).foregroundStyle(.secondary) } label: { Label(item.name, systemImage: item.symbol) }
                    }
                    if preview.protected.isEmpty { Text("Nothing running is protected by name right now.").foregroundStyle(.secondary) }
                } header: { Text(Names.Guard.protectedNow) }
            }
            .formStyle(.grouped)
        } else {
            LoadingState("Looking at what is running…")
        }
    }

    private func color(_ state: RuleState) -> Color {
        switch state {
        case .acting: .green
        case .watching: .blue
        case .off: .secondary
        case .cantRun: .orange
        }
    }
}

/// Steps 4 to 6: one permission, as the row Setup shows it, with its action (and the System Settings hand-off) in place.
struct WelcomePermissionStep: View {
    let model: WelcomeModel
    let actions: SetupActions
    let handoff: SystemSettingsHandoff
    let ids: [String]

    var body: some View {
        Form {
            Section {
                ForEach(ids.compactMap { model.item($0) }) { item in
                    SetupItemRow(item: item, working: actions.working == item.id, busy: actions.working != nil,
                                 session: handoff.session(item.id), confirmed: handoff.confirmed.contains(item.id),
                                 onAction: { Task { await actions.perform(item) } },
                                 onCloseGuidance: { handoff.dismiss(item.id) },
                                 // the primary button asks for notifications and Time Machine; only a hand-off belongs in the row
                                 showsAction: handsOff(item))
                }
            } footer: {
                if let message = actions.message {
                    Text(message)
                } else if ids == ["fullDiskAccess"] {
                    Text("Not Now is fine: reports still work, and the folders it can't see are named above.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func handsOff(_ item: SetupItem) -> Bool {
        if case .openSettings = item.action { return true }
        return false
    }
}

/// The last step: what is on now, one line each, and what was skipped with where to turn it on.
struct WelcomeDoneStep: View {
    let model: WelcomeModel

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.step) { row in
                    HStack(alignment: .top, spacing: Tokens.Space.m) {
                        Image(systemName: row.on ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(row.on ? Tokens.Status.safe.tint : Tokens.Status.inert.tint)
                            .imageScale(.large)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                            Text(row.title).font(.callout.weight(.medium))
                            Text(row.on ? row.evidence : "You can turn this on in Setup.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, Tokens.Space.xs)
                }
            }
        }
        .formStyle(.grouped)
    }

    private struct Row { let step: WelcomeStep; let title: String; let on: Bool; let evidence: String }

    /// Read now, not remembered from earlier in the flow.
    private var rows: [Row] {
        let background = model.items.filter { $0.id.hasPrefix("job.") }
        let loaded = background.filter { $0.state == .on }.count
        var result = [Row(step: .background, title: Names.Welcome.stepBackground, on: !background.isEmpty && loaded == background.count,
                          evidence: "\(loaded) of \(background.count) background jobs are loaded.")]
        result.append(Row(step: .guardPreview, title: Names.Welcome.stepGuard, on: model.state.answers[WelcomeStep.guardPreview.rawValue] == .done,
                          evidence: "You have seen what it would do. For now it only watches."))
        for (step, id) in [(WelcomeStep.notifications, "notifications"), (.fullDiskAccess, "fullDiskAccess"), (.timeMachine, "timeMachine")] {
            guard model.steps.contains(step), let item = model.item(id) else { continue }
            result.append(Row(step: step, title: step.title, on: item.state == .on, evidence: item.evidence))
        }
        return result
    }
}
