import AppKit
import AnalyzersKit

/// First run: the Welcome flow when the Mac is new to the app or an update has something new to set up, else Setup when
/// something is broken.
extension AppDelegate {

    /// Decided from what is on this Mac now and what the person has already been shown (`WelcomePlanner`):
    /// - a new install: the whole Welcome flow;
    /// - an update that adds steps that are not satisfied: the flow, with only those;
    /// - an update on a Mac that is already set up: nothing;
    /// - a Mac whose background jobs are not installed: Setup, instead of an Overview that reports nothing.
    /// A tool that sets the defaults key `welcome.neverOpen` (a test, a render) never gets a window from this.
    func presentWelcomeOrSetup() {
        Task { @MainActor in
            let setup = await SetupInputs.read()
            let reach = await TimeMachineDestination.current()
            let inputs = WelcomeSatisfaction.inputs(
                setup: setup, state: SetupState.load(), hasTimeMachine: WelcomeSatisfaction.hasTimeMachine(reach),
                version: BuildInfo.current.release,
                neverOpen: UserDefaults.standard.bool(forKey: WelcomePlanner.neverOpenKey))
            if WelcomePlanner.autoPlan(inputs) != nil {
                WelcomeRequest.open(.automatic)
                return
            }
            guard !inputs.neverOpen, !WelcomePlanner.isFreshInstall(inputs) else { return }
            let engine = await Task.detached(priority: .userInitiated) { EngineStatus.probe() }.value
            if !engine.isFullyInstalled { SettingsOpener.open(target: "setup") }
        }
    }
}
