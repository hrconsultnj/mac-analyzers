import Foundation
import ServiceManagement
import UserNotifications

/// Everything Setup reads, in one value: what the system, the disk and launchd said, right now. The rows are a pure
/// function of this (`SetupItems.build`), so a probe judges every state on a fixture and the screen shows the same
/// rows from the live read or from a fixture.
public struct SetupInputs: Sendable {

    public enum Notifications: Sendable, Equatable {
        /// Running without an app bundle, so the notification center cannot be asked.
        case unavailable
        case notAsked
        case denied
        case allowedAlertsOff
        case allowed
    }

    public enum Login: Sendable, Equatable {
        case enabled, requiresApproval, notFound, notRegistered
    }

    public struct Job: Sendable, Equatable {
        public let label: String
        public let loaded: Bool
        /// The installed schedule in words, nil when it is not installed.
        public let schedule: String?
        /// When its log was last written.
        public let lastActivity: Date?
        public init(label: String, loaded: Bool, schedule: String?, lastActivity: Date?) {
            self.label = label
            self.loaded = loaded
            self.schedule = schedule
            self.lastActivity = lastActivity
        }
    }

    public var engineFound = true
    public var usingBundledEngine = false
    /// The guard first, then the cleaners, in `EngineStatus` order.
    public var jobs: [Job] = []
    public var notifications = Notifications.allowed
    public var login = Login.enabled
    public var fdaApp: [String: PlaceOutcome] = [:]
    /// What the background jobs last saw of them (`BackgroundAccess`); nil until a job has run and said.
    public var fdaAgent: [String: PlaceOutcome]?
    public var fdaAgentChecked: Date?
    public var timeMachineAllowed = false
    /// The Automation row is a remembered flag, not a read: it goes with the check behind gate G1 (blueprint §2.5).
    public var automationProven = false
    public var settingsFileExists = true
    public var capMB = 6144
    public var installedMB = 32 * 1024
    public var neverClose: [String] = []
    public var mayQuit: [String] = []
    /// The recording sources switched on, by name, and how many of them are waiting for access to a guarded folder.
    public var recordingSourcesOn: [String] = []
    public var recordingSourcesNeedAccess = 0
    public var now = Date()

    public init() {}

    /// The real answers. Slow reads run off the main actor.
    @MainActor
    public static func read() async -> SetupInputs {
        var inputs = SetupInputs()
        let config = ConfigStore()
        let readings = await Task.detached(priority: .userInitiated) { () -> (EngineStatus, [String: PlaceOutcome], (checked: Date, places: [String: PlaceOutcome])?) in
            (EngineStatus.probe(), FullDiskAccessProbe.check(), BackgroundAccess.read())
        }.value
        let engine = readings.0
        inputs.engineFound = engine.suiteRootExists && engine.scriptsPresent
        inputs.usingBundledEngine = AnalyzersPaths.usingBundledEngine
        let logs: [(String, EngineLog)] = [(EngineStatus.guardLabel, .guardLog),
                                           (EngineStatus.cleanerLabels[0], .memoryClean),
                                           (EngineStatus.cleanerLabels[1], .storageClean),
                                           (EngineStatus.cleanerLabels[2], .storageClean)]
        inputs.jobs = logs.map { label, log in
            let loaded = label == EngineStatus.guardLabel ? engine.guardAgent == .loaded : engine.cleanerAgents[label] == .loaded
            let modified = log.url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            return Job(label: label, loaded: loaded, schedule: ScheduleKit.isInstalled(label) ? ScheduleKit.describe(label) : nil,
                       lastActivity: modified)
        }
        inputs.fdaApp = readings.1
        inputs.fdaAgent = readings.2?.places
        inputs.fdaAgentChecked = readings.2?.checked

        inputs.notifications = await notificationReading()
        switch SMAppService.mainApp.status {
        case .enabled: inputs.login = .enabled
        case .requiresApproval: inputs.login = .requiresApproval
        case .notFound: inputs.login = .notFound
        default: inputs.login = .notRegistered
        }
        inputs.timeMachineAllowed = await TimeMachinePermission.isAllowed()
        inputs.automationProven = UserDefaults.standard.bool(forKey: "automationProven")   // pending removal, §2.5
        inputs.settingsFileExists = FileManager.default.fileExists(atPath: AnalyzersPaths.configLocal.path)
        inputs.installedMB = Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024)
        inputs.capMB = ConfigReader.intValue(forKey: "GUARD_HARD_CAP_MB") ?? 6144
        inputs.neverClose = ConfigReader.listValue(forKey: "ANALYZERS_PROTECT_EXTRA")
        inputs.mayQuit = ConfigReader.listValue(forKey: "ANALYZERS_RECLAIM_APPS")

        // the recording sources: only what is saved counts, and nothing in a guarded folder is looked at
        let saved = config.storage.recordingSources + (config.storage.recordingSourcesConfigured || config.storage.recordingsDir.isEmpty
            ? [] : [RecordingSourceEntry(id: RecordingSource.customID, enabled: true, path: config.storage.recordingsDir)])
        let keys = Set(saved.map(\.key))
        let found = RecordingDiscovery.discover(readers: .live(), saved: saved).filter { keys.contains($0.id) && $0.enabled }
        var apps = found.filter { !$0.isCustom }.map(\.title)
        let own = found.filter(\.isCustom).count
        if own > 0 { apps.append("\(own) \(own == 1 ? "folder" : "folders") of yours") }
        inputs.recordingSourcesOn = apps
        inputs.recordingSourcesNeedAccess = found.filter { if case .needsAccess = $0.access { true } else { false } }.count
        return inputs
    }

    fileprivate static func notificationReading() async -> Notifications {
        // a bare executable has no app bundle, and the notification center throws without one (a tool quirk)
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return settings.alertSetting == .enabled ? .allowed : .allowedAlertsOff
        case .denied: return .denied
        default: return .notAsked
        }
    }
}

extension SetupInputs {
    /// Just one row's answer, read again: what the hand-off to System Settings watches while a person is switching
    /// something on there. Cheap enough to ask every two seconds.
    public static func state(of pane: SetupPane) async -> SetupItemState {
        switch pane {
        case .fullDiskAccess:
            return await Task.detached(priority: .userInitiated) {
                FullDiskAccessProbe.verdict(app: FullDiskAccessProbe.check(), agent: nil).state
            }.value
        case .notifications:
            return await notificationReading() == .allowed ? .on : .off
        case .loginItems:
            return SMAppService.mainApp.status == .enabled ? .on : .needsYou
        case .automation:
            return UserDefaults.standard.bool(forKey: "automationProven") ? .on : .cantTell     // pending removal, §2.5
        }
    }
}
