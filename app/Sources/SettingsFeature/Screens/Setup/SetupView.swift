import AppKit
import SwiftUI
import AnalyzersKit
import NotifierKit
import UIComponents

/// Setup: the current configuration of Mac Analyzers on this Mac, as three tabs: **Permissions** (what macOS or you
/// control), **Background** (what runs on its own) and **Protection** (the choices that decide what it may touch). One row
/// per thing, each with its state, the evidence for it and one action; rows that need you come first. Every row is READ
/// (`SetupInputs.read`), never assumed, and a row that only System Settings can change hands you there, says exactly what to
/// switch on and confirms when it is done (`SystemSettingsHandoff`).
///
/// This file is the screen's state and composition. Next to it:
///   SetupItemRow.swift             one row: state, evidence, the one button, and the hand-off guidance in place
///   SystemSettingsHandoff.swift    opening the exact pane, watching for the change, confirming
///   SetupView+Repairs.swift        the action behind each row's button
///   UninstallView.swift            Turn Off or Remove, reached from this screen's toolbar
struct SetupView: View {

    @Environment(GuardLogStore.self) var store
    @Environment(Navigator.self) var navigator
    @Environment(JobStore.self) var jobs
    @State var inputs: SetupInputs?
    @State var tab = SetupTab.permissions
    @State var working: String?
    /// The install job this screen shows: the store's own, found again by kind when the window is reopened mid-run.
    @State var installJob: Job?
    @State var message: String?
    @State var messageIsError = false
    @State var handoff = SystemSettingsHandoff()
    @State private var highlighted: String?
    /// An example state for `SnapshotRunner` (`SetupFixtures.names`); nil in the app, which reads this Mac.
    var fixture: String?

    private var items: [SetupItem] { inputs.map(SetupItems.build) ?? [] }

    var body: some View {
        DataScreen(title: Names.Screen.setup, subtitle: inputs == nil ? nil : SetupItems.subtitle(items)) {
            if inputs == nil {
                LoadingState("Checking this Mac…")
            } else {
                ScrollViewReader { proxy in
                    List {
                        if let installJob, installJob.isActive {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(installJob.step ?? "Installing the background jobs…").foregroundStyle(.secondary)
                                Spacer()
                                Button("Stop") { installJob.cancel() }
                            }
                        }
                        if let message {
                            Label(message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(messageIsError ? Tokens.Status.destructive.tint : Tokens.Status.safe.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(SetupItems.items(items, in: tab)) { item in
                            SetupItemRow(item: item, working: working == item.id, busy: working != nil,
                                         session: handoff.session(item.id), confirmed: handoff.confirmed.contains(item.id),
                                         onAction: { Task { await perform(item) } },
                                         onCloseGuidance: { handoff.dismiss(item.id) })
                                .id(item.id)
                                .listRowBackground(highlighted == item.id ? Color.accentColor.opacity(0.12) : nil)
                        }
                    }
                    .listStyle(.inset)
                    .onChange(of: highlighted) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                }
            }
        }
        .scopeTabsToolbar(screen: "setup", items: tabItems, selection: $tab)
        .toolbar {
            ToolbarItem {
                Button { navigator.push(.overview(.turnOff)) } label: { Label(Names.Setup.turnOffOrRemove, systemImage: "power") }
                    .labelStyle(.titleAndIcon)
                    .help("Pause, turn off or remove Mac Analyzers' background protection")
            }
            .toolbarRank(.secondary)
        }
        .task {
            handoff.onChange = { await load() }
            await adoptRunningInstall()
            await load()
            applyPendingLink()
        }
        .task { await handoff.listenForActivation() }
        .onChange(of: navigator.pendingIntent) { applyPendingLink() }
        .onDisappear { for id in Array(handoff.sessions.keys) { handoff.dismiss(id) } }
    }

    private var tabItems: [ScopeTabItem<SetupTab>] {
        SetupTab.allCases.map { ScopeTabItem(value: $0, title: $0.title, symbol: $0.symbol, count: SetupItems.needing(items, in: $0)) }
    }

    /// Reads this Mac again (or takes the example state).
    func load() async {
        if let fixture { inputs = SetupFixtures.inputs(fixture); return }
        inputs = await SetupInputs.read(agentRunner: Self.agentRunner)
    }

    /// The `agent-runner` the background jobs run as, next to this app's own program.
    private static var agentRunner: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "agent-runner")
    }

    /// A deep link: a tab (`setup:permissions`) or a row (`setup:fullDiskAccess`).
    private func applyPendingLink() {
        guard let payload = navigator.takeIntent(for: OverviewGroup.setup) else { return }
        if let target = SetupTab(rawValue: payload) {
            tab = target
            ScopeTabMemory.select(target.rawValue, in: "setup")
        } else if let item = items.first(where: { $0.id == payload }) {
            tab = item.tab
            ScopeTabMemory.select(item.tab.rawValue, in: "setup")
            highlighted = item.id
        }
    }
}
