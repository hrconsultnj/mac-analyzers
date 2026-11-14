import Foundation

/// The steps of the Welcome flow, in order. Each has the version that introduced it, so an update shows only what is new.
public enum WelcomeStep: String, CaseIterable, Codable, Sendable, Hashable {
    case welcome, background, guardPreview, notifications, fullDiskAccess, timeMachine, done

    public var title: String {
        switch self {
        case .welcome: Names.Welcome.stepWelcome
        case .background: Names.Welcome.stepBackground
        case .guardPreview: Names.Welcome.stepGuard
        case .notifications: Names.Welcome.stepNotifications
        case .fullDiskAccess: Names.Welcome.stepFullDiskAccess
        case .timeMachine: Names.Welcome.stepTimeMachine
        case .done: Names.Welcome.stepDone
        }
    }

    public var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .background: "clock.arrow.2.circlepath"
        case .guardPreview: "shield.lefthalf.filled"
        case .notifications: "bell.badge"
        case .fullDiskAccess: "internaldrive"
        case .timeMachine: "clock.arrow.circlepath"
        case .done: "checkmark.circle"
        }
    }

    /// One sentence under the title: why this step exists.
    public var sentence: String {
        switch self {
        case .welcome: "Mac Analyzers watches your Mac's memory, keeps its storage tidy and shows what starts by itself. Here is what that looks like on this Mac."
        case .background: "Memory is watched all the time and storage is tidied on a schedule, without you opening anything."
        case .guardPreview: "Memory Guard looks at what is running. Here is what it would do on this Mac right now. For now it only watches."
        case .notifications: "Mac Analyzers tells you when it stops something and when it needs your decision, and each notification has buttons to act on it."
        case .fullDiskAccess: "Without it the storage report can't see some folders, and under-reports what is using your disk."
        case .timeMachine: "Lets Mac Analyzers delete Time Machine's local snapshots when the disk is full, without asking for your password each time."
        case .done: "Here is how Mac Analyzers is set up now. You can change any of it later in Setup."
        }
    }

    /// The step has nothing to answer: an introduction or a summary.
    public var isFraming: Bool { self == .welcome || self == .done }
    /// The step only informs (the guard preview shows what would happen and changes nothing): it is part of the flow on a new
    /// install, and never a reason to open the window after an update.
    public var isInformational: Bool { self == .welcome || self == .guardPreview || self == .done }
    /// Only offered, never nagged about after an update.
    public var isOptional: Bool { self == .timeMachine }
}

/// A step and the version that introduced it.
public struct WelcomeSpec: Sendable, Equatable {
    public let step: WelcomeStep
    public let introducedIn: String
    public init(step: WelcomeStep, introducedIn: String) {
        self.step = step
        self.introducedIn = introducedIn
    }

    /// The release that FIRST had the thing each step asks for, so an install that already has it is not asked again: Setup
    /// (background jobs, notifications, Full Disk Access) came in 2.61.0, Time Machine thinning in 2.70.0; only the welcome, the
    /// guard preview and the summary are new in 2.72.0.
    public static let all: [WelcomeSpec] = [
        WelcomeSpec(step: .welcome, introducedIn: "2.72.0"),
        WelcomeSpec(step: .background, introducedIn: "2.61.0"),
        WelcomeSpec(step: .guardPreview, introducedIn: "2.72.0"),
        WelcomeSpec(step: .notifications, introducedIn: "2.61.0"),
        WelcomeSpec(step: .fullDiskAccess, introducedIn: "2.61.0"),
        WelcomeSpec(step: .timeMachine, introducedIn: "2.70.0"),
        WelcomeSpec(step: .done, introducedIn: "2.72.0"),
    ]
}

/// Which steps show, and why.
public struct WelcomePlan: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// A new install: the whole flow.
        case firstLaunch
        /// An update added steps that are not satisfied: only those.
        case newInThisVersion
        /// The person asked to carry on from Setup.
        case continuing
    }

    public let reason: Reason
    public let steps: [WelcomeStep]
    /// The step to open on.
    public let start: Int

    public init(reason: Reason, steps: [WelcomeStep], start: Int) {
        self.reason = reason
        self.steps = steps
        self.start = start
    }

    public var title: String { reason == .newInThisVersion ? Names.Welcome.newInThisVersion : Names.Welcome.windowTitle }
}

/// What the person's Mac says about each step, and what they have been shown.
public struct WelcomeInputs: Sendable {
    public var state: SetupState?
    public var version = "2.72.0"
    public var configExists = false
    public var anyJobLoaded = false
    /// Steps already satisfied by what is on this Mac (read live).
    public var satisfied: Set<WelcomeStep> = []
    /// This Mac has a Time Machine backup disk set up.
    public var hasTimeMachine = false
    /// The defaults key the tools set so no window ever opens on its own during a test or a render.
    public var neverOpen = false
    public var specs = WelcomeSpec.all

    public init() {}
}

public enum WelcomePlanner {
    /// The version an install is taken to have been shown when it has no record: the release before this flow existed.
    public static let baseline = "2.71.0"

    /// The defaults key a tool sets (`-welcome.neverOpen YES`) to stop the flow opening itself. Read once, here.
    public static let neverOpenKey = "welcome.neverOpen"

    /// A new install is one with no record, no settings file and no background job.
    public static func isFreshInstall(_ i: WelcomeInputs) -> Bool { i.state == nil && !i.configExists && !i.anyJobLoaded }

    /// When the flow opens by itself (at launch), and with which steps. Nil: it does not.
    public static func autoPlan(_ i: WelcomeInputs) -> WelcomePlan? {
        if i.neverOpen { return nil }
        if isFreshInstall(i) {
            let steps = i.specs.map(\.step).filter { !($0 == .timeMachine && !i.hasTimeMachine) }
            return WelcomePlan(reason: .firstLaunch, steps: steps, start: 0)
        }
        // never again on its own once finished
        if i.state?.finished == true { return nil }
        let seen = i.state?.seenVersion ?? baseline
        let answered = Set((i.state?.answers ?? [:]).keys)
        let new = i.specs.filter { isNewer($0.introducedIn, than: seen) }.map(\.step)
            .filter { !$0.isInformational && !$0.isOptional && !i.satisfied.contains($0) && !answered.contains($0.rawValue) }
        guard !new.isEmpty else { return nil }
        return WelcomePlan(reason: .newInThisVersion, steps: new + [.done], start: 0)
    }

    /// What to do at launch: a new install opens the window (it is the first launch, and the flow is what the person came for);
    /// an update that has something new does NOT take focus, it badges Setup and waits for the person to open the app; anything
    /// else does nothing.
    public enum LaunchAction: Equatable, Sendable {
        case openWindow(WelcomePlan)
        case badgeSetup
        case nothing
    }

    public static func launchAction(_ i: WelcomeInputs) -> LaunchAction {
        guard let plan = autoPlan(i) else { return .nothing }
        return plan.reason == .firstLaunch ? .openWindow(plan) : .badgeSetup
    }

    /// The version to save when the flow is shown: the current release, or the newest version that introduced a step if that is
    /// later. A development build is numbered as the release before the one it is heading to, so saving only the release would
    /// leave steps "newer" than the saved version and the flow would come back on every launch.
    public static func stampVersion(current: String, specs: [WelcomeSpec] = WelcomeSpec.all) -> String {
        specs.map(\.introducedIn).reduce(current) { isNewer($1, than: $0) ? $1 : $0 }
    }

    /// Setup's Continue Setup…: the steps still not satisfied, from the first one with no answer, else the first skipped.
    public static func continuePlan(_ i: WelcomeInputs) -> WelcomePlan? {
        let open = i.specs.map(\.step).filter { !$0.isFraming && !i.satisfied.contains($0) && !($0 == .timeMachine && !i.hasTimeMachine) }
        guard !open.isEmpty else { return nil }
        let steps = open + [.done]
        let answers = i.state?.answers ?? [:]
        let start = open.firstIndex { answers[$0.rawValue] == nil } ?? 0
        return WelcomePlan(reason: .continuing, steps: steps, start: start)
    }

    /// The What's New card in the sidebar reads this defaults key: a new install is taken to have seen the version it came
    /// with, so the card is never shown on a first install. Sets it only when there is none. True when it was set.
    @discardableResult
    public static func markWhatsNewSeen(version: String, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.string(forKey: whatsNewSeenKey) == nil else { return false }
        defaults.set(version, forKey: whatsNewSeenKey)
        return true
    }

    public static let whatsNewSeenKey = "whatsNew.seenVersion"

    /// Dotted numbers compared as numbers: "2.72.0" is newer than "2.9.1".
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(x.count, y.count) {
            let l = index < x.count ? x[index] : 0, r = index < y.count ? y[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}
