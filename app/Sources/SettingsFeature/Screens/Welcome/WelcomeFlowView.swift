import AnalyzersKit
import SwiftUI
import UIComponents

/// The Welcome flow: its own window, shown on a new install and, after an update, with only the steps that are new and not
/// yet satisfied. Every step has the same shape: a symbol, a title and one sentence, a form of live rows, and a bottom bar
/// (Step n of m, Back, Set Up Later, Not Now, and the step's one primary button).
///
/// What each step shows is READ from this Mac through the same rows Setup shows (`SetupInputs`, `SetupItems`), and a
/// permission is handed to System Settings the same way (`SystemSettingsHandoff`): one source of truth, no second checker.
///
/// Next to this file:
///   WelcomeModel.swift        the steps, where it is, what is read, what is saved
///   WelcomeSteps.swift        what each step shows
///   WelcomeBottomBar.swift    the bar: Step n of m and the buttons
public struct WelcomeFlowView: View {
    @Environment(GuardLogStore.self) private var store
    @Environment(JobStore.self) private var jobs
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var model = WelcomeModel()
    @State private var actions = SetupActions()
    @State private var handoff = SystemSettingsHandoff()
    @State private var working = false

    /// An example (`fresh:3`) for `SnapshotRunner`; nil in the app.
    private let fixture: String?

    public init(fixture: String? = nil) { self.fixture = fixture }

    public var body: some View {
        VStack(spacing: 0) {
            if let plan = model.plan, let step = model.step {
                header(plan, step)
                Divider()
                content(step)
                Divider()
                WelcomeBottomBar(position: model.index + 1, count: model.steps.count, isFirst: model.index == 0, isLast: model.index == model.steps.count - 1,
                                 step: step, primary: primaryTitle(step), busy: working,
                                 back: { model.back() }, later: leave, notNow: { Task { await model.answer(.skipped) } },
                                 primaryAction: { Task { await primary(step) } })
            } else {
                LoadingState("Checking this Mac…")
            }
        }
        // a window sized to its content needs a definite size: one for every step, so it does not jump as the steps change
        .frame(width: 560, height: 680)
        .task {
            model.fixture = fixture
            actions.isFixture = fixture != nil
            actions.bind(jobs: jobs, store: store, navigator: nil, handoff: handoff, reload: { await model.refresh() })
            handoff.onChange = { await model.refresh() }
            let mode = WelcomeRequest.mode
            WelcomeRequest.mode = .automatic
            await model.start(mode: mode)
        }
        .task { await handoff.listenForActivation() }
        .onDisappear { for id in Array(handoff.sessions.keys) { handoff.dismiss(id) } }
    }

    private func header(_ plan: WelcomePlan, _ step: WelcomeStep) -> some View {
        VStack(spacing: Tokens.Space.s) {
            if plan.reason == .newInThisVersion {
                Text(plan.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Image(systemName: step.symbol)
                .font(.system(size: 34))      // the step's symbol: an icon, so its size is the job
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(step.title).font(.title2.weight(.semibold))
            Text(step.sentence)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.l)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func content(_ step: WelcomeStep) -> some View {
        switch step {
        case .welcome: WelcomeIntroStep(numbers: model.numbers)
        case .background: WelcomeBackgroundStep(model: model)
        case .guardPreview: WelcomeGuardStep(preview: model.preview)
        case .notifications: WelcomePermissionStep(model: model, actions: actions, handoff: handoff, ids: ["notifications"])
        case .fullDiskAccess: WelcomePermissionStep(model: model, actions: actions, handoff: handoff, ids: ["fullDiskAccess"])
        case .timeMachine: WelcomePermissionStep(model: model, actions: actions, handoff: handoff, ids: ["timeMachine"])
        case .done: WelcomeDoneStep(model: model)
        }
    }

    // MARK: - the buttons

    private func primaryTitle(_ step: WelcomeStep) -> String {
        switch step {
        case .background: model.isSatisfied(.background) ? Names.Welcome.next : Names.Welcome.turnOn
        case .guardPreview: Names.Welcome.useTheseSettings
        case .timeMachine: model.item("timeMachine")?.state == .on ? Names.Welcome.next : Names.Setup.allow
        case .done: Names.Welcome.openMacAnalyzers
        default: Names.Welcome.next
        }
    }

    private func primary(_ step: WelcomeStep) async {
        working = true
        defer { working = false }
        switch step {
        case .background:
            if model.isSatisfied(.background) { await model.answer(.done); return }
            // turned on, or said why not: it only moves on once the jobs are really loaded
            if await model.turnOnBackground(actions: actions) { await model.answer(.done) }
        case .notifications:
            // one button before macOS's own prompt, never "Allow" (the prompt is macOS's)
            if model.setup?.notifications == .notAsked, let item = model.item("notifications") { await actions.perform(item) }
            await model.refresh()
            await model.answerForWhatIsTrue()
        case .timeMachine:
            if model.item("timeMachine")?.state != .on, let item = model.item("timeMachine") { await actions.perform(item); await model.refresh() }
            await model.answerForWhatIsTrue()
        case .guardPreview:
            await model.answer(.done)
        case .done:
            model.finish()
            if fixture == nil {
                openWindow(id: "main")
                dismissWindow(id: "welcome")
            }
        default:
            await model.answerForWhatIsTrue()
        }
    }

    private func leave() {
        model.leave()
        if fixture == nil { dismissWindow(id: "welcome") }
    }
}
