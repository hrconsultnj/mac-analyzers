import SwiftUI
import AnalyzersKit

/// Where a row's Quit or Stop goes. The panel signals nothing itself: pressing asks `MemoryStop` for a plan from
/// the live process table (`PanelStop`); a refusal is said under the table in its own sentence; a plan that needs the
/// person's yes is confirmed there with the plan's own title, detail and action word before anything is sent; and a
/// program that did not stop is never forced from here: Monitor is offered, where Force Stop has its own question.
/// Nothing is kept past the panel closing, so a confirmation that was open is gone and nothing was sent.
@MainActor @Observable
final class PanelStopFlow {
    /// A plan waiting for the person's yes, and the group it is for.
    private(set) var asking: MemoryStop.Pending?
    private var askingGroup = ""
    /// What the last press said.
    private(set) var said: String?
    /// Where Monitor opens on the program, when the panel cannot finish the job itself.
    private(set) var monitorLink: String?
    private(set) var working = false

    func begin(_ group: CensusGroup) {
        said = nil
        monitorLink = nil
        askingGroup = group.name
        switch PanelStop.begin(group: group) {
        case .ask(let plan): asking = plan
        case .say(let why): said = why
        case .openMonitor(let reason, let link):
            said = reason
            monitorLink = link
        }
    }

    func cancel() { asking = nil }

    func confirm(reload: @escaping () -> Void) {
        guard let plan = asking else { return }
        asking = nil
        working = true
        let group = askingGroup
        Task { @MainActor in
            let done = await PanelStop.confirm(plan, group: group)
            said = done.message
            monitorLink = done.monitorLink
            reload()
            working = false
        }
    }
}

/// The confirmation and the notice, under the table.
struct MenuStopPrompt: View {
    let flow: PanelStopFlow
    let reload: () -> Void

    var body: some View {
        if let plan = flow.asking {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title).font(.callout.weight(.semibold))
                    Text(plan.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { flow.cancel() }
                            .keyboardShortcut(.cancelAction)
                        Button(plan.actionTitle) { flow.confirm(reload: reload) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        if let said = flow.said {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(said).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let link = flow.monitorLink {
                    Button("Open in \(Names.Screen.monitor)") { SettingsOpener.open(target: link) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }
}
