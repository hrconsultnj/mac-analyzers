import AnalyzersKit
import Foundation
import ServiceManagement
import SwiftUI

/// The Welcome flow's state: which steps show and why, where it is, what the Mac says (the same `SetupInputs` Setup reads,
/// so there is one reading of the Mac), and what the person has answered, saved in `setup-state.json` as they go.
@MainActor @Observable
final class WelcomeModel {

    private(set) var setup: SetupInputs?
    private(set) var numbers: WelcomeNumbers?
    private(set) var preview: GuardPreview?
    private(set) var plan: WelcomePlan?
    var index = 0
    private(set) var state = SetupState(seenVersion: WelcomePlanner.baseline)
    /// "Open Mac Analyzers when you log in": on unless the person turns it off on the Background step.
    var openAtLogin = true
    private(set) var version = BuildInfo.current.release

    /// An example (`fresh:3`: that state, that step): nothing is read from this Mac and nothing is saved.
    var fixture: String?

    var items: [SetupItem] { setup.map(SetupItems.build) ?? [] }
    var steps: [WelcomeStep] { plan?.steps ?? [] }
    var step: WelcomeStep? { steps.isEmpty ? nil : steps[min(index, steps.count - 1)] }

    func item(_ id: String) -> SetupItem? { items.first { $0.id == id } }

    // MARK: - starting

    /// Reads the Mac and decides the steps. `mode` is what asked for the window.
    func start(mode: WelcomeRequest.Mode) async {
        if let fixture { startFixture(fixture); return }
        let setup = await SetupInputs.read()
        self.setup = setup
        let reach = await TimeMachineDestination.current()
        let saved = SetupState.load()
        let inputs = WelcomeSatisfaction.inputs(setup: setup, state: saved, hasTimeMachine: WelcomeSatisfaction.hasTimeMachine(reach),
                                                version: version, neverOpen: false)
        var chosen: WelcomePlan?
        switch mode {
        case .automatic: chosen = WelcomePlanner.autoPlan(inputs)
        case .continuing: chosen = WelcomePlanner.continuePlan(inputs)
        case .again: break
        }
        // asked for by hand with nothing to carry on with: the whole flow again
        let plan = chosen ?? allSteps(inputs)
        self.plan = plan
        index = plan.start
        numbers = WelcomeNumbers.read()
        state = saved ?? SetupState(seenVersion: version)
        // the flow has been shown: an update is not shown the same steps again, and a new install's What's New card is not
        // needed (the version it came with is the one it is already running)
        state.seenVersion = WelcomePlanner.stampVersion(current: version)
        state.save()
        if plan.reason == .firstLaunch, mode == .automatic { WelcomePlanner.markWhatsNewSeen(version: version) }
        await loadPreviewIfNeeded()
    }

    private func allSteps(_ inputs: WelcomeInputs) -> WelcomePlan {
        WelcomePlan(reason: .firstLaunch, steps: inputs.specs.map(\.step).filter { !($0 == .timeMachine && !inputs.hasTimeMachine) }, start: 0)
    }

    private func startFixture(_ name: String) {
        let parts = name.split(separator: ":").map(String.init)
        let fixtureState = parts.first ?? "fresh"
        let (setup, welcome) = SetupFixtures.welcome(fixtureState)
        self.setup = setup
        numbers = .fixture
        preview = .fixture
        let chosen: WelcomePlan?
        switch fixtureState {
        case "upgraded": chosen = WelcomePlanner.autoPlan(welcome)
        case "continuing": chosen = WelcomePlanner.continuePlan(welcome)
        default: chosen = WelcomePlanner.autoPlan(welcome)
        }
        plan = chosen
        let wanted = parts.count > 1 ? (Int(parts[1]) ?? 1) - 1 : (chosen?.start ?? 0)
        index = min(max(wanted, 0), max((chosen?.steps.count ?? 1) - 1, 0))
        state = welcome.state ?? SetupState(seenVersion: "2.72.0")
    }

    func refresh() async {
        guard fixture == nil else { return }
        setup = await SetupInputs.read()
    }

    private func loadPreviewIfNeeded() async {
        guard fixture == nil, preview == nil, steps.contains(.guardPreview), let setup else { return }
        let limit = setup.capMB
        preview = await Task.detached(priority: .userInitiated) { GuardPreview.read(limitMB: limit) }.value
    }

    // MARK: - moving

    func back() { if index > 0 { index -= 1 } }

    /// Records the answer to the step on screen and moves on. A step that only introduces or sums up has no answer to record.
    func answer(_ answer: SetupState.Answer) async {
        guard let step else { return }
        if !step.isFraming, fixture == nil {
            state.record(step, answer)
            state.save()
        }
        if index < steps.count - 1 { index += 1; await loadPreviewIfNeeded() }
    }

    /// Done by what is true now: a step the Mac has satisfied is "done", one still open is "skipped".
    func answerForWhatIsTrue() async {
        guard let step else { return }
        await answer(isSatisfied(step) ? .done : .skipped)
    }

    func isSatisfied(_ step: WelcomeStep) -> Bool {
        guard let setup else { return false }
        return WelcomeSatisfaction.inputs(setup: setup, state: state, hasTimeMachine: true, version: version).satisfied.contains(step)
    }

    /// The last step: the flow is finished and will not appear again by itself.
    func finish() {
        guard fixture == nil else { return }
        state.finished = true
        state.save()
    }

    /// Set Up Later: leave now; what was not reached is left as it was.
    func leave() {
        guard fixture == nil else { return }
        state.save()
    }

    // MARK: - the background step

    /// Installs the background jobs (one tracked job) and, unless turned off, registers the login item. True when every
    /// job is loaded afterwards.
    func turnOnBackground(actions: SetupActions) async -> Bool {
        if let guardJob = item("job.\(EngineStatus.guardLabel)"), guardJob.action == .installAgents {
            await actions.perform(guardJob)
        }
        if openAtLogin, fixture == nil, SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        await refresh()
        return setup.map { $0.jobs.allSatisfy(\.loaded) } ?? false
    }
}
