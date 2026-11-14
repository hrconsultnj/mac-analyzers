import Foundation

/// The three kinds of thing Setup holds, as the shared scope tabs: what macOS or the person controls (Permissions), what
/// runs on its own (Background), and the choices that decide what Mac Analyzers may touch (Protection).
public enum SetupTab: String, CaseIterable, Sendable, Hashable {
    case permissions, background, protection

    public var title: String {
        switch self {
        case .permissions: Names.Setup.tabPermissions
        case .background: Names.Setup.tabBackground
        case .protection: Names.Setup.tabProtection
        }
    }

    public var symbol: String {
        switch self {
        case .permissions: "lock.shield"
        case .background: "clock.arrow.2.circlepath"
        case .protection: "hand.raised"
        }
    }
}

/// Where a row stands, as a symbol and a word. Every state is the answer to a read, never a remembered assumption.
public enum SetupItemState: Sendable, Equatable {
    case on
    case off
    case needsYou
    case notAskedYet
    case cantTell
    /// Full Disk Access only: the app can read the folders but the background jobs cannot.
    case onlyApp

    public var label: String {
        switch self {
        case .on: Names.Setup.stateOn
        case .off: Names.Setup.stateOff
        case .needsYou: Names.Setup.stateNeedsYou
        case .notAskedYet: Names.Setup.stateNotAskedYet
        case .cantTell: Names.Setup.stateCantTell
        case .onlyApp: Names.Setup.stateOnlyApp
        }
    }

    public var symbol: String {
        switch self {
        case .on: "checkmark.circle.fill"
        case .off: "circle.slash"
        case .needsYou: "exclamationmark.triangle.fill"
        case .notAskedYet: "questionmark.circle"
        case .cantTell: "minus.circle"
        case .onlyApp: "exclamationmark.circle.fill"
        }
    }

    /// Something the person can do about it: the rows that come first and the number on the tab.
    public var needsPerson: Bool { self != .on && self != .cantTell }
}

/// A pane of System Settings the product can only hand the person to, and what to say there.
public enum SetupPane: String, Sendable, Equatable {
    case fullDiskAccess, notifications, loginItems, automation

    /// Where it is, in the words the person will read on screen.
    public var path: String {
        switch self {
        case .fullDiskAccess: "Privacy & Security › Full Disk Access"
        case .notifications: "Notifications › Mac Analyzers"
        case .loginItems: "General › Login Items & Extensions"
        case .automation: "Privacy & Security › Automation"
        }
    }

    /// What to switch on there.
    public var instruction: String {
        switch self {
        case .fullDiskAccess: "switch on Mac Analyzers"
        case .notifications: "switch on Allow Notifications, and choose Banners or Alerts"
        case .loginItems: "switch on Mac Analyzers under Allow in the Background"
        case .automation: "switch on the apps Mac Analyzers is listed under"
        }
    }

    /// Whether the app can be dragged into the pane's list (Full Disk Access has no request, and macOS 27.3 may not list
    /// the app on its own).
    public var offersDrag: Bool { self == .fullDiskAccess }

    /// The links to try in order: the form of the current macOS, the older one, then System Settings itself.
    public var links: [String] {
        switch self {
        case .fullDiskAccess:
            ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
             "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles", "x-apple.systempreferences:"]
        case .notifications:
            ["x-apple.systempreferences:com.apple.Notifications-Settings.extension", "x-apple.systempreferences:"]
        case .loginItems:
            // the app asks `SMAppService.openSystemSettingsLoginItems()` instead; these are the fallback
            ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension", "x-apple.systempreferences:"]
        case .automation:
            ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
             "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation", "x-apple.systempreferences:"]
        }
    }
}

/// The one button of a row.
public enum SetupAction: Sendable, Equatable {
    case installAgents
    case allowNotifications
    case sendTest
    case enableLogin
    case timeMachineAllow
    case timeMachineRemove
    case setMemoryCap(Int)
    /// A deep link to the screen that changes it.
    case change(String)
    case showInActivity(String)
    case writeConfig
    /// Hands the person to System Settings, says what to switch on, and watches for the change.
    case openSettings(SetupPane)
}

/// What a row's state was read from. A row that is only a remembered flag is not a detection, and the probe fails on one.
public enum SetupSource: Sendable, Equatable {
    /// The system answered (notifications, the login item, a read of a folder).
    case system
    /// A file on disk (the settings file, the engine's scripts, a plist).
    case file
    /// launchd.
    case launchd
    /// A flag the app remembers. `pendingRemoval` is the Automation row, which goes once the check that no permission
    /// prompt appears has passed (blueprint §2.5, gate G1).
    case remembered(pendingRemoval: Bool)

    public var isRead: Bool { if case .remembered = self { false } else { true } }
}

/// One thing Setup shows: its state, the evidence for it, and at most one action.
public struct SetupItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let tab: SetupTab
    public let title: String
    /// One sentence on what it gets the person.
    public let why: String
    public let state: SetupItemState
    /// What was read, never a promise.
    public let evidence: String
    public let action: SetupAction?
    public let actionTitle: String?
    public let source: SetupSource

    public init(id: String, tab: SetupTab, title: String, why: String, state: SetupItemState, evidence: String,
                action: SetupAction? = nil, actionTitle: String? = nil, source: SetupSource) {
        self.id = id
        self.tab = tab
        self.title = title
        self.why = why
        self.state = state
        self.evidence = evidence
        self.action = action
        self.actionTitle = actionTitle
        self.source = source
    }
}
