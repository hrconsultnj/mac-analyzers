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
///   SetupActions.swift             the action behind each row's button (shared with the Welcome flow)
///   UninstallView.swift            Turn Off or Remove, reached from this screen's toolbar
struct SetupView: View {

    @Environment(GuardLogStore.self) var store
    @Environment(Navigator.self) var navigator
    @Environment(JobStore.self) var jobs
    @State var inputs: SetupInputs?
    @State var tab = SetupTab.permissions
    @State var actions = SetupActions()
    @State var handoff = SystemSettingsHandoff()
    @State private var highlighted: String?
    /// An example state for `SnapshotRunner` (`SetupFixtures.names`); nil in the app, which reads this Mac.
    var fixture: String?

    private var items: [SetupItem] { inputs.map(SetupItems.build) ?? [] }

    /// A step of the Welcome flow is still open: Continue Setup… is offered. (Not from an example state.)
    private var continuing: Bool {
        guard fixture == nil, let inputs else { return false }
        let welcome = WelcomeSatisfaction.inputs(setup: inputs, state: SetupState.load(), hasTimeMachine: false, version: BuildInfo.current.release)
        // Time Machine is optional: only the steps that matter make "Continue Setup…" worth offering
        return WelcomePlanner.continuePlan(welcome) != nil && SetupState.exists()
    }

    var body: some View {
        DataScreen(title: Names.Screen.setup, subtitle: inputs == nil ? nil : SetupItems.subtitle(items)) {
            if inputs == nil {
                LoadingState("Checking this Mac…")
            } else {
                ScrollViewReader { proxy in
                    List {
                        if let installJob = actions.installJob, installJob.isActive {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(installJob.step ?? "Installing the background jobs…").foregroundStyle(.secondary)
                                Spacer()
                                Button("Stop") { installJob.cancel() }
                            }
                        }
                        if let message = actions.message {
                            Label(message, systemImage: actions.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(actions.messageIsError ? Tokens.Status.destructive.tint : Tokens.Status.safe.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(SetupItems.items(items, in: tab)) { item in
                            SetupItemRow(item: item, working: actions.working == item.id, busy: actions.working != nil,
                                         session: handoff.session(item.id), confirmed: handoff.confirmed.contains(item.id),
                                         onAction: { Task { await actions.perform(item) } },
                                         onCloseGuidance: { handoff.dismiss(item.id) })
                                .id(item.id)
                                .listRowBackground(highlighted == item.id ? Color.accentColor.opacity(0.12) : nil)
                        }
                        // what the old checklist said at its foot, in one line
                        Text("Come back here whenever something stops working: permissions can be withdrawn in System Settings at any time, and macOS can switch background jobs off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listStyle(.inset)
                    .onChange(of: highlighted) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                }
            }
        }
        .scopeTabsToolbar(screen: "setup", items: tabItems, selection: $tab)
        .toolbar {
            // carry on with the steps still open (a skipped one that is still not satisfied), where the flow left off
            if continuing {
                ToolbarItem {
                    Button { WelcomeRequest.open(.continuing) } label: { Label(Names.Welcome.continueSetup, systemImage: "arrow.right.circle") }
                        .labelStyle(.titleAndIcon)
                        .help("Carry on with the steps of the Welcome flow you haven't finished")
                }
                .toolbarRank(.primary)
            }
            ToolbarItem {
                Button { navigator.push(.overview(.turnOff)) } label: { Label(Names.Setup.turnOffOrRemove, systemImage: "power") }
                    .labelStyle(.titleAndIcon)
                    .help("Pause, turn off or remove Mac Analyzers' background protection")
            }
            .toolbarRank(.secondary)
        }
        .task {
            actions.bind(jobs: jobs, store: store, navigator: navigator, handoff: handoff, reload: { await load() })
            actions.isFixture = fixture != nil
            handoff.onChange = { await load() }
            await actions.adoptRunningInstall()
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
        inputs = await SetupInputs.read()
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
