import Foundation

/// Example states of Setup for a probe and for looking at the screen headless. Each is a `SetupInputs`, so the rows come
/// from the same function as the live ones and can never show a shape the screen does not get.
public enum SetupFixtures {

    public static let names = ["allOn", "allOff", "waiting", "appOnly", "noReport"]

    private static func jobs(loaded: Bool) -> [SetupInputs.Job] {
        let now = Date()
        return [SetupInputs.Job(label: EngineStatus.guardLabel, loaded: loaded, schedule: loaded ? "Always on" : nil,
                                lastActivity: loaded ? now.addingTimeInterval(-600) : nil),
                SetupInputs.Job(label: EngineStatus.cleanerLabels[0], loaded: loaded, schedule: loaded ? "Every day at 4:00" : nil,
                                lastActivity: loaded ? now.addingTimeInterval(-3 * 3600) : nil),
                SetupInputs.Job(label: EngineStatus.cleanerLabels[1], loaded: loaded, schedule: loaded ? "Every day at 4:30" : nil,
                                lastActivity: loaded ? now.addingTimeInterval(-5 * 3600) : nil),
                SetupInputs.Job(label: EngineStatus.cleanerLabels[2], loaded: loaded, schedule: loaded ? "Every 7 days" : nil,
                                lastActivity: loaded ? now.addingTimeInterval(-3 * 86_400) : nil)]
    }

    private static func places(_ outcome: PlaceOutcome) -> [String: PlaceOutcome] {
        Dictionary(uniqueKeysWithValues: ProtectedPlaces.all.map { ($0.id, outcome) })
    }

    public static func inputs(_ name: String) -> SetupInputs {
        var inputs = SetupInputs()
        inputs.jobs = jobs(loaded: true)
        inputs.fdaApp = places(.readable)
        inputs.fdaAgent = places(.readable)
        inputs.fdaAgentChecked = Date().addingTimeInterval(-3 * 3600)
        inputs.timeMachineAllowed = true
        inputs.automationProven = true
        inputs.neverClose = ["superwhisper", "MacAnalyzers", "Logic Pro"]
        inputs.mayQuit = ["Docker"]
        inputs.recordingSourcesOn = ["Zoom", "Screen Recordings", "1 folder of yours"]
        switch name {
        case "allOff":
            inputs.jobs = jobs(loaded: false)
            inputs.notifications = .notAsked
            inputs.login = .notRegistered
            inputs.fdaApp = places(.denied)
            inputs.fdaAgent = nil
            inputs.fdaAgentChecked = nil
            inputs.timeMachineAllowed = false
            inputs.automationProven = false
            inputs.settingsFileExists = false
            inputs.capMB = 12 * 1024
            inputs.neverClose = []
            inputs.mayQuit = []
            inputs.recordingSourcesOn = []
        case "waiting":
            // waiting for the person in System Settings: the login item needs approval, notifications and Full Disk Access are off
            inputs.notifications = .denied
            inputs.login = .requiresApproval
            inputs.fdaApp = places(.denied)
            inputs.recordingSourcesNeedAccess = 1
        case "appOnly":
            // the app can read the folders, the background jobs can't
            inputs.fdaAgent = places(.denied)
            inputs.notifications = .allowedAlertsOff
        case "noReport":
            // the app can read the folders; no background job has run since the report was added, so nothing is known of them
            inputs.fdaAgent = nil
            inputs.fdaAgentChecked = nil
        default: break
        }
        return inputs
    }

    /// The Welcome flow in an example state (`fresh`, `upgraded`, `continuing`): its steps and what the Mac says.
    public static let welcomeStates = ["fresh", "upgraded", "continuing"]

    public static func welcome(_ name: String) -> (setup: SetupInputs, welcome: WelcomeInputs) {
        switch name {
        case "upgraded":
            // an update that brought a step to set up (Full Disk Access, pretended to be new): the flow shows only that
            var setup = inputs("waiting")
            setup.notifications = .allowed
            setup.login = .enabled
            var welcome = WelcomeSatisfaction.inputs(setup: setup, state: SetupState(seenVersion: WelcomePlanner.baseline),
                                                      hasTimeMachine: true, version: "2.72.0")
            // no step but the welcome and the guard preview is new in this release, so a later release is pretended here: the one
            // that first asks for Full Disk Access, which this Mac has not given
            welcome.specs = WelcomeSpec.all.map { $0.step == .fullDiskAccess ? WelcomeSpec(step: .fullDiskAccess, introducedIn: "2.72.0") : $0 }
            return (setup, welcome)
        case "continuing":
            // flow left half-way: notifications answered, Full Disk Access skipped and still off
            var setup = inputs("waiting")
            setup.notifications = .allowed
            var state = SetupState(seenVersion: "2.72.0")
            state.record(.welcome, .done); state.record(.background, .done); state.record(.guardPreview, .done)
            state.record(.notifications, .done); state.record(.fullDiskAccess, .skipped)
            let welcome = WelcomeSatisfaction.inputs(setup: setup, state: state, hasTimeMachine: true, version: "2.72.0")
            return (setup, welcome)
        default:
            // a new install: nothing set up yet
            var setup = inputs("allOff")
            setup.jobs = setup.jobs.map { SetupInputs.Job(label: $0.label, loaded: false, schedule: nil, lastActivity: nil) }
            setup.settingsFileExists = false
            let welcome = WelcomeSatisfaction.inputs(setup: setup, state: nil, hasTimeMachine: true, version: "2.72.0")
            return (setup, welcome)
        }
    }
}
