import Foundation

/// The knobs a job's engine script takes, as data. Two jobs have the "same
/// options" when these compare equal — that is what ties an apply to the
/// preview the user reviewed.
public struct JobOptions: Sendable, Hashable, Codable {

    /// Storage clean: the engine's deep mode (stale node_modules, idle
    /// worktrees, package caches) plus Time Machine snapshot release.
    public var deep = false

    /// Temp & Agents: delete instead of moving to the Trash.
    public var permanent = false

    /// Eject: the mount point inside a temp folder.
    public var mountPoint: String?

    /// Recordings: prune recording folders older than this many days.
    public var recordingsDays = 90

    /// Memory cleanup: also end busy orphaned tools, not only idle ones
    /// (`--orphans-all`).
    public var includeBusyOrphans = false

    /// Memory cleanup, "everything now": also ask these apps to quit, by name
    /// (`--apps-list`). Empty adds nothing. The names are part of what the
    /// preview was, so an apply carries exactly the same list.
    public var alsoQuit: [String] = []

    /// A scheduled run replayed by hand ("Run Now"): the arguments from the
    /// installed launchd plist, after the script path. The store fills this in
    /// itself from the plist for a `.schedule(label)` run, and ignores whatever a
    /// caller put here: they usually include `--apply`.
    public var scheduleArguments: [String]?

    public init(deep: Bool = false, permanent: Bool = false, mountPoint: String? = nil,
                recordingsDays: Int = 90, scheduleArguments: [String]? = nil,
                includeBusyOrphans: Bool = false, alsoQuit: [String] = []) {
        self.deep = deep
        self.permanent = permanent
        self.mountPoint = mountPoint
        self.recordingsDays = recordingsDays
        self.scheduleArguments = scheduleArguments
        self.includeBusyOrphans = includeBusyOrphans
        self.alsoQuit = alsoQuit
    }
}
