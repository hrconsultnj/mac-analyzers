import Foundation

/// What an installed copy follows when it looks for something newer. A person picks one on the Updates
/// screen; Releases is the default and is what the app has always done.
public enum UpdateChannel: String, CaseIterable, Sendable, Identifiable {
    /// The newest published release.
    case releases
    /// The newest commit on the `development` branch on GitHub, committed or not yet released.
    case beta
    /// The clone this copy was built from, including what is not committed yet.
    case thisCopy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .releases: Names.Channel.releases
        case .beta: Names.Channel.beta
        case .thisCopy: Names.Channel.thisCopy
        }
    }

    public static let defaultsKey = "updateChannel"

    public static var saved: UpdateChannel {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(UpdateChannel.init(rawValue:)) ?? .releases
    }
}

/// Where a Beta or This Copy channel leaves this copy. Releases has no such state: it compares
/// version numbers (`UpdateChecker.isNewer`).
public enum ChannelState: Equatable, Sendable {
    /// The channel cannot be followed from this copy, in a sentence ("downloaded, not built from a clone").
    case unavailable(String)
    /// This copy has what the channel offers.
    case upToDate
    /// The channel has something this copy lacks. `changes` is how many commits, when known;
    /// `uncommitted` says the clone also has changes that are not committed.
    case behind(changes: Int?, uncommitted: Bool)
    /// Built from the same commit, but not from the same files (uncommitted changes added or gone), or from
    /// a commit this clone does not have.
    case differs(String)
    /// This copy has changes the channel does not: it is ahead.
    case ahead(String)
    /// The answer could not be read (offline).
    case unknown(String)

    /// Offers the install button.
    public var isUpdate: Bool {
        switch self {
        case .behind, .differs: true
        default: false
        }
    }
}

/// How the installed commit relates to a clone's head.
public enum CloneRelation: Equatable, Sendable {
    /// The clone's head is the install's commit.
    case same
    /// The clone has this many commits the install does not.
    case cloneAhead(Int)
    /// The install has this many commits the clone does not (the clone was reset or is on another branch).
    case installAhead(Int)
    /// The install's commit is not in the clone, or the two have gone different ways.
    case unrelated
}

/// What a clone looks like right now, read with plain git by `SourceClone`.
public struct CloneFacts: Equatable, Sendable {
    public var branch: String?
    public var isDirty: Bool
    /// "clean", or a hash of the uncommitted changes (the same one the build stamps).
    public var fingerprint: String
    public var relation: CloneRelation

    public init(branch: String?, isDirty: Bool, fingerprint: String, relation: CloneRelation) {
        self.branch = branch
        self.isDirty = isDirty
        self.fingerprint = fingerprint
        self.relation = relation
    }
}

/// What GitHub's compare of the installed commit with `development` answered.
public struct BetaCompare: Equatable, Sendable, Codable {
    /// "ahead" (development has more), "identical", "behind" (this copy has more), "diverged",
    /// or "missing" (GitHub does not know the commit).
    public var status: String
    public var aheadBy: Int
    /// The newest commit on development: its short hash, date and first line.
    public var newest: String?

    public init(status: String, aheadBy: Int, newest: String? = nil) {
        self.status = status
        self.aheadBy = aheadBy
        self.newest = newest
    }
}

/// The words-free rules of the two development channels: facts in, one state out, so a probe can run every case.
public enum ChannelLogic {

    /// Beta: the newest commit on `development` against the commit this copy was built from.
    /// Only a clone on `development` can follow it, because installing is `git pull` on that branch.
    public static func beta(build: BuildInfo, cloneBranch: String?, isClone: Bool, compare: BetaCompare?) -> ChannelState {
        guard isClone else { return .unavailable(Names.ChannelText.notAClone) }
        guard cloneBranch == "development" else {
            return .unavailable(Names.ChannelText.notOnDevelopment(cloneBranch))
        }
        guard build.commit != nil else {
            // an older build that never recorded its commit: one install from here starts the record
            return .behind(changes: nil, uncommitted: false)
        }
        guard let compare else { return .unknown(Names.ChannelText.offline) }
        switch compare.status {
        case "rateLimited": return .unknown(Names.ChannelText.rateLimited)
        case "identical":
            // the commit is the newest, but a build with uncommitted changes in it is not "the newest beta"
            return build.localChanges || build.localChangesUnknown ? .ahead(Names.ChannelText.builtWithLocalChanges) : .upToDate
        case "ahead": return .behind(changes: compare.aheadBy, uncommitted: false)
        case "behind": return .ahead(Names.ChannelText.aheadOfDevelopment)
        case "missing": return .ahead(Names.ChannelText.notOnGitHub)
        default: return .ahead(Names.ChannelText.divergedFromDevelopment)
        }
    }

    /// This Copy: the clone this build came from, uncommitted changes included.
    public static func thisCopy(build: BuildInfo, isClone: Bool, clone: CloneFacts?) -> ChannelState {
        guard isClone else { return .unavailable(Names.ChannelText.notAClone) }
        // a clone that git could not be read in is unknown, never "clean": a wrong "up to date" hides work
        guard let clone else { return .unknown(Names.ChannelText.cannotRead) }
        guard build.commit != nil else { return .behind(changes: nil, uncommitted: clone.isDirty) }
        let installedFingerprint = build.treeHash ?? (build.localChanges ? "unknown" : "clean")
        switch clone.relation {
        case .cloneAhead(let count):
            return .behind(changes: count, uncommitted: clone.isDirty)
        case .installAhead:
            return .differs(Names.ChannelText.cloneIsBehindInstall)
        case .unrelated:
            return .differs(Names.ChannelText.cloneLacksCommit)
        case .same:
            if clone.fingerprint == installedFingerprint { return .upToDate }
            if clone.isDirty { return .behind(changes: 0, uncommitted: true) }
            return .differs(Names.ChannelText.installHadChangesCloneLost)
        }
    }
}
