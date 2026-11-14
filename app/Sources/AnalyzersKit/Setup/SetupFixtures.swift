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
}
