import Foundation

/// What a process IS inside the category the census put it in: a browser, a dev server, a macOS service.
/// One kind per group, read from `memory-analyzer/rules/kinds.json` by `KindCatalog`; the Monitor, the
/// menu-bar panel, the guard and `agent-runner --probe-kinds` all read this one field, so nothing
/// classifies a second time.
public struct ProcessKind: Identifiable, Sendable, Hashable {

    /// What the guard may do to it by itself: ask it to quit (an app), ask it to stop (a program), or nothing.
    public enum StopsWith: String, Sendable, Hashable { case quit, stop, none }

    /// "tools.devServers": the category, then the kind.
    public let id: String
    public let category: CensusGroup.Category
    public let devTooling: Bool
    public let stopsWith: StopsWith
    /// Seconds a stop is given before what is left is ended; nil means never forced.
    public let forceAfterGrace: Int?
    /// What the guard is meant to be allowed to do to it, as a sentence (the probe prints it). The guard script does
    /// not read the kinds yet: this is the policy the catalog carries, not what the script does today.
    public let guardMay: String
    /// Why Monitor leaves it alone or handles it with care, as a sentence; nil when nothing is held back.
    public let leftAlone: String?

    /// The kind's name on screen (`Names.Kind`).
    public var name: String { Names.Kind.name(forID: id) ?? id }

    public static func == (lhs: ProcessKind, rhs: ProcessKind) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Which rule put a process in its kind, and whether that rule rests on an identity the system gives
/// or only on a name.
public struct KindMatch: Sendable {

    public enum Basis: String, Sendable {
        /// A bundle identifier, an executable, a program path, a launchd job, an account.
        case identity
        /// Only the words of a name or command line: nothing better exists, and the kind says why.
        case name
        /// No rule matched: the category's "other" kind.
        case fallback
    }

    public let kind: ProcessKind
    public let basis: Basis
    /// The rule in words: "exe node", "bundleId io.tailscale.ipn", "argv mcp", "no rule matched".
    public let rule: String
}

/// Everything recognition needs to know about one process or one app. The census fills it in from the
/// kernel and the app's Info.plist; the probe fills it in by hand, so the same rules judge both.
public struct ProcessSubject: Sendable {
    /// The executable's path, or "pid N" when the kernel will not say.
    public let path: String
    /// The command line when it was read, else the path.
    public let command: String
    public let uid: UInt32
    public let me: UInt32
    public let ppid: Int
    /// The process's own number, for the rules that ask whether it is the very process launchd runs for a job.
    public let pid: Int
    /// The app's bundle identifier and category (`LSApplicationCategoryType`), for a process that belongs to an app.
    public let bundleID: String?
    public let appCategory: String?
    /// The app's name, as the census groups it.
    public let appName: String?
    public let appPath: String?

    public init(path: String, command: String? = nil, uid: UInt32, me: UInt32, ppid: Int = 0, pid: Int = 0,
                bundleID: String? = nil, appCategory: String? = nil, appName: String? = nil, appPath: String? = nil) {
        self.path = path
        self.command = command ?? path
        self.uid = uid
        self.me = me
        self.ppid = ppid
        self.pid = pid
        self.bundleID = bundleID
        self.appCategory = appCategory
        self.appName = appName
        self.appPath = appPath
    }
}
