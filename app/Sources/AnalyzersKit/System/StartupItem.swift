import Foundation

/// One thing that starts by itself on this Mac: a login item, a launch agent
/// or daemon, or a helper tool. Plain data. The audit script decides what is
/// wrong with an item (`finding`, `reason`); this type only gives that
/// decision words a person can read.
public struct StartupItem: Identifiable, Hashable, Sendable {

    public enum Kind: String, Sendable, CaseIterable {
        case loginItem, launchAgent, launchDaemon, helperTool

        public var title: String {
            switch self {
            case .loginItem: Names.Startup.loginItem
            case .launchAgent: Names.Startup.launchAgent
            case .launchDaemon: Names.Startup.launchDaemon
            case .helperTool: Names.Startup.helperTool
            }
        }

        /// One sentence on what the kind is, for the inspector.
        public var summary: String {
            switch self {
            case .loginItem: "An app that opens when you log in, listed under Open at Login in System Settings."
            case .launchAgent: "A background program that starts when you log in."
            case .launchDaemon: "A background program that starts when the Mac starts, for every user."
            case .helperTool: "A program an app installed so it can do work that needs administrator rights."
            }
        }

        /// The word the audit script writes in its inventory.
        init?(token: String) {
            switch token {
            case "loginitem": self = .loginItem
            case "agent": self = .launchAgent
            case "daemon": self = .launchDaemon
            case "helper": self = .helperTool
            default: return nil
            }
        }
    }

    /// Whose folder the item lives in. Removing a `system` item needs an
    /// administrator; the app never does that for you.
    public enum Scope: String, Sendable {
        case user, system
    }

    /// How the item is doing right now, as launchd reports it.
    public enum State: String, Sendable {
        case running, loaded, notLoaded, disabled, enabled

        public var title: String {
            switch self {
            case .running: Names.Startup.running
            case .loaded: Names.Startup.loaded
            case .notLoaded: Names.Startup.notLoaded
            case .disabled: Names.Startup.disabled
            case .enabled: Names.Startup.enabled
            }
        }

        init(token: String) {
            switch token {
            case "running": self = .running
            case "loaded": self = .loaded
            case "disabled": self = .disabled
            case "enabled": self = .enabled
            default: self = .notLoaded
            }
        }
    }

    /// What the audit concluded. A `leftover` is what the script calls an
    /// orphan: the program the item starts is gone, so it can never run again.
    public enum Finding: String, Sendable {
        case fine, leftover, possibleLeftover, notChecked, removed

        public var title: String? {
            switch self {
            case .fine: nil
            case .leftover: Names.Startup.leftover
            case .possibleLeftover: Names.Startup.possibleLeftover
            case .notChecked: Names.Startup.notChecked
            case .removed: Names.Startup.removed
            }
        }

        /// Sorting: the things that need a look come first.
        public var rank: Int {
            switch self {
            case .leftover: 0
            case .possibleLeftover: 1
            case .notChecked: 2
            case .removed: 3
            case .fine: 4
            }
        }

        init(token: String) {
            switch token {
            case "orphan": self = .leftover
            case "leftover": self = .possibleLeftover
            case "skip": self = .notChecked
            case "removed": self = .removed
            default: self = .fine
            }
        }
    }

    /// Why the audit flagged it, as the script's code.
    public enum Reason: String, Sendable {
        case targetMissing = "target-missing"
        case noVendorApp = "no-vendor-app"
        case noProgramKey = "no-program-key"
        case notAbsolute = "not-absolute"
        case driveNotConnected = "drive-not-connected"
        case otherDisk = "other-disk"
        case unusualPath = "unusual-path"
        case none = ""
    }

    public let id: String
    public let kind: Kind
    public let scope: Scope
    /// The launchd label, helper file name or login item name.
    public let label: String
    public let plistPath: String?
    public let targetPath: String?
    public let finding: Finding
    public let state: State
    public let reason: Reason
    /// The exact command the script prints for a system item it flagged.
    public let fixCommand: String?

    /// What the item is called, for a person.
    public private(set) var name: String
    /// The app or developer it belongs to.
    public let owner: String
    /// Where `owner` came from, so it can be checked.
    public enum OwnerSource: String, Sendable {
        case app = "app", signature = "signature", installFolder = "folder", label = "label"
    }

    public let ownerSource: OwnerSource
    /// Set when a code signature named an owner but did not validate.
    public let ownerNote: String?
    /// The app bundle it belongs to (outermost `.app` in its program path),
    /// whether or not that app still exists. Used for the icon.
    public let appPath: String?

    /// The screen's categories: what KIND of thing a person is looking at. A
    /// leftover is a leftover whatever it is; the rest are apps that open
    /// themselves and the background programs working for them.
    public enum Category: String, Sendable, CaseIterable, Identifiable {
        case apps, background, leftovers

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .apps: Names.Startup.categoryApps
            case .background: Names.Startup.categoryBackground
            case .leftovers: Names.Startup.categoryLeftovers
            }
        }

        public var symbol: String {
            switch self {
            case .apps: "app.badge.checkmark"
            case .background: "gearshape.2"
            case .leftovers: "questionmark.folder"
            }
        }
    }

    public var category: Category {
        switch finding {
        case .leftover, .possibleLeftover: .leftovers
        default: kind == .loginItem ? .apps : .background
        }
    }

    public var needsAdministrator: Bool { scope == .system }

    /// Only a user-level leftover can be removed from here: the same scope
    /// `login-items-audit.sh --apply` has. A system item shows its command.
    public var canRemove: Bool { scope == .user && finding == .leftover }

    /// What the audit's approved-list names this item by: the plist for an
    /// agent, the app path for a login item.
    public var removalKey: String? {
        guard canRemove else { return nil }
        return plistPath ?? targetPath
    }

    /// The file Finder should reveal: the plist, or the program when there is
    /// no plist, whichever exists.
    public var revealPath: String? {
        [plistPath, targetPath].compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    public var stateTitle: String { state.title }
    public var findingTitle: String { finding.title ?? "" }

    /// Where it lives, in words.
    public var whereItLives: String {
        switch kind {
        case .loginItem: "Open at Login in System Settings"
        case .launchAgent:
            scope == .user ? "Your LaunchAgents folder" : "The LaunchAgents folder for all users"
        case .launchDaemon: "The LaunchDaemons folder"
        case .helperTool: "The PrivilegedHelperTools folder"
        }
    }

    /// Why it is or is not flagged, as sentences.
    public var explanation: String {
        switch finding {
        case .fine:
            return "Nothing wrong was found. The program it starts is there"
                + (kind == .loginItem ? "." : " and an app from the same developer is installed.")
        case .removed:
            return "This leftover was removed. It cannot start again."
        case .leftover:
            let base = "The program it starts is gone, so it can never run. Nothing depends on it."
            return needsAdministrator
                ? base + " Removing it needs an administrator, so Mac Analyzers shows the command instead of running it."
                : base
        case .possibleLeftover:
            return "The program is still there, but no app from the same developer is installed any more, so it is probably left over from an app you removed. Look before you remove it."
        case .notChecked:
            switch reason {
            case .noProgramKey: return "Its settings don't say which program to run, so the audit can't check it. Leave it alone unless you know it is unwanted."
            case .notAbsolute: return "It starts a program by name rather than by location, so the audit can't check it."
            case .otherDisk: return "A disk with the same name as the program's disk is connected, but the folder the program belongs in is not on it, so this may be a different disk. It is not called a leftover."
            case .driveNotConnected: return "Its program is on a drive that isn't connected right now, so it is not a leftover. Connect the drive and audit again."
            case .unusualPath: return "Its name or location contains a tab or a line break, which the audit cannot record safely, so it is never touched from here."
            default: return "The audit couldn't check this item."
            }
        }
    }

    /// The same item with a title that tells it apart from a twin in its group.
    func renamed(_ name: String) -> StartupItem {
        var copy = self
        copy.name = name
        return copy
    }

    public init(id: String, kind: Kind, scope: Scope, label: String, plistPath: String?,
                targetPath: String?, finding: Finding, state: State, reason: Reason,
                fixCommand: String?, name: String, owner: String, ownerSource: OwnerSource,
                ownerNote: String? = nil, appPath: String?) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.label = label
        self.plistPath = plistPath
        self.targetPath = targetPath
        self.finding = finding
        self.state = state
        self.reason = reason
        self.fixCommand = fixCommand
        self.name = name
        self.owner = owner
        self.ownerSource = ownerSource
        self.ownerNote = ownerNote
        self.appPath = appPath
    }
}
