import Foundation

/// What is already true on this Mac, as the Welcome flow's steps see it: built from the same rows Setup shows
/// (`SetupItems`), so there is one reading of the Mac and the flow never disagrees with Setup.
public enum WelcomeSatisfaction {

    public static func inputs(setup: SetupInputs, state: SetupState?, hasTimeMachine: Bool, version: String,
                              neverOpen: Bool = false) -> WelcomeInputs {
        let items = SetupItems.build(setup)
        func item(_ id: String) -> SetupItem? { items.first { $0.id == id } }
        var satisfied: Set<WelcomeStep> = [.welcome, .done]
        // the background jobs: the engine is there and every job is loaded
        if setup.engineFound, !setup.jobs.isEmpty, setup.jobs.allSatisfy(\.loaded) { satisfied.insert(.background) }
        // notifications: macOS has been asked (allowed or refused); a refusal is an answer
        if setup.notifications != .notAsked { satisfied.insert(.notifications) }
        // Full Disk Access: readable, or nothing on this Mac to tell by
        if let fda = item("fullDiskAccess"), fda.state == .on || fda.state == .cantTell { satisfied.insert(.fullDiskAccess) }
        if setup.timeMachineAllowed || !hasTimeMachine { satisfied.insert(.timeMachine) }
        // the guard preview is satisfied by an answer: it has no state of its own on this Mac
        if state?.answers[WelcomeStep.guardPreview.rawValue] != nil { satisfied.insert(.guardPreview) }
        var inputs = WelcomeInputs()
        inputs.state = state
        inputs.version = version
        inputs.configExists = setup.settingsFileExists
        inputs.anyJobLoaded = setup.jobs.contains(where: \.loaded)
        inputs.satisfied = satisfied
        inputs.hasTimeMachine = hasTimeMachine
        inputs.neverOpen = neverOpen
        return inputs
    }

    /// Whether this Mac has a Time Machine backup disk set up (mounted or not).
    public static func hasTimeMachine(_ reach: TimeMachineDestination.Reach) -> Bool { reach == .connected || reach == .notConnected }
}

/// What opened the Welcome window, so it shows the right steps: by itself at launch, Setup's Continue Setup…, or the Help
/// menu's Show Welcome Again…. Set just before the window is asked for, and read (and cleared) by the window when it appears.
@MainActor
public enum WelcomeRequest {
    public enum Mode: Sendable { case automatic, continuing, again }
    public static var mode = Mode.automatic

    /// Asks for the window.
    public static func open(_ mode: Mode) {
        self.mode = mode
        SettingsOpener.open(target: "welcome")
    }
}
