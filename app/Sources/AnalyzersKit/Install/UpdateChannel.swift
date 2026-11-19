import Foundation

/// What an installed copy follows when it looks for something newer. A person picks one on the Updates
/// screen; Releases is the default and is what the app has always done.
public enum UpdateChannel: String, CaseIterable, Sendable, Identifiable {
    /// The newest published release.
    case releases
    /// The newest beta: the newest GitHub pre-release (tag `vX.Y.Z-beta.N`), or a newer release when one is out.
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
    /// Beta: a published version newer than this copy exists; the text is its short name ("2.72.1 Beta 2").
    case offered(String)
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
        case .behind, .differs, .offered: true
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

/// What GitHub's list of releases answered, for Beta: the newest pre-release that is a beta (`vX.Y.Z-beta.N`)
/// and the newest release that is not a pre-release, each as a version without the "v".
public struct BetaFeed: Equatable, Sendable, Codable {
    /// "ok", or "rateLimited" when GitHub is limiting this network.
    public var status: String
    /// "2.72.1-beta.2": the newest published beta, or nil when none has been published.
    public var newestBeta: String?
    /// "2.72.0": the newest published release.
    public var newestRelease: String?

    public init(status: String = "ok", newestBeta: String? = nil, newestRelease: String? = nil) {
        self.status = status
        self.newestBeta = newestBeta
        self.newestRelease = newestRelease
    }

    /// What Beta offers: the newer of the newest beta and the newest release. A beta is only ever the newest
    /// when it is past the release (2.72.1-beta.1 sorts above 2.72.0 and below 2.72.1), so once a release catches up
    /// with its beta, the release is what is offered.
    public var target: String? {
        switch (newestBeta, newestRelease) {
        case let (beta?, release?): UpdateChecker.isNewer(release, than: beta) ? release : beta
        case let (beta?, nil): beta
        case let (nil, release?): release
        default: nil
        }
    }
}

/// Whether a copy's commit already holds a published beta's commit (GitHub's compare of the beta's tag with the commit).
public enum BetaContainment: Equatable, Sendable, Codable {
    /// The copy's commit is the beta's or comes after it: it has everything the beta has.
    case contains
    /// The copy's commit is behind the beta or has gone another way: it lacks something the beta has.
    case lacks
}

/// The words-free rules of the two development channels: facts in, one state out, so a probe can run every case.
public enum ChannelLogic {

    /// Beta: the newest GitHub pre-release (or a newer release) against the version of this copy, by semantic-versioning
    /// precedence: 2.72.0 < 2.72.1-beta.1 < 2.72.1-beta.2 < 2.72.1-dev.N < 2.72.1. A development copy is therefore
    /// never offered a beta it is past, and every copy is offered the release once it is published. Only a clone on
    /// `development` can follow it, because installing is a fast-forward of that branch to the tag.
    ///
    /// A development copy of the same version is above every beta of it by precedence alone, so for it the version cannot
    /// say whether it has the newest beta: `containment` does (the copy's commit against the beta's). A Dev copy that lacks
    /// the beta is offered it; one that holds it is ahead; when that could not be read (a commit GitHub does not know, or
    /// offline) it is ahead, never offered something it may already hold.
    public static func beta(build: BuildInfo, cloneBranch: String?, isClone: Bool, feed: BetaFeed?,
                            containment: BetaContainment? = nil) -> ChannelState {
        guard isClone else { return .unavailable(Names.ChannelText.notAClone) }
        guard cloneBranch == "development" else {
            return .unavailable(Names.ChannelText.notOnDevelopment(cloneBranch))
        }
        guard let feed else { return .unknown(Names.ChannelText.offline) }
        if feed.status == "rateLimited" { return .unknown(Names.ChannelText.rateLimited) }
        guard let target = feed.target else { return .unavailable(Names.ChannelText.noBetaYet) }
        let installed = build.version
        switch UpdateChecker.compare(target, installed) {
        case .orderedDescending:
            return .offered(BuildInfo.label(forVersion: target))
        case .orderedSame:
            // the newest thing published is this copy: a beta is "the newest beta"; a release means no beta is out
            return feed.newestBeta == target ? .upToDate : .unavailable(Names.ChannelText.noBetaYet)
        case .orderedAscending:
            if build.isDevelopment, let beta = feed.newestBeta, beta == target, containment == .lacks {
                return .offered(BuildInfo.label(forVersion: target))
            }
            return .ahead(feed.newestBeta == nil ? Names.ChannelText.aheadOfRelease : Names.ChannelText.aheadOfBeta)
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
