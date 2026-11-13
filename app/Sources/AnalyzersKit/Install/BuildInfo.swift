import Foundation

/// How far this copy is from the last release, as one value every surface
/// reads: the Update screen, the sidebar, the menu footer and What's New.
///
/// The version string only changes at a release, so a build made weeks later
/// reads the same. `build.sh` stamps the nearest release tag, the commits made
/// since it and whether the tree had local changes; a copy with no stamp (a
/// download, or a build with no git history) reads as a release.
public struct BuildInfo: Sendable, Equatable {

    /// The release number, "2.68.1".
    public let release: String
    /// Commits made after the release tag. nil: no stamp, so a release.
    public let commitsAfter: Int?
    public let localChanges: Bool
    /// The commit this copy was built from (full hash), the branch it was on, and "clean" or a hash of the
    /// uncommitted changes it was built with. nil for a copy built before these were stamped, or a download.
    public let commit: String?
    public let branch: String?
    public let treeHash: String?

    public init(release: String, commitsAfter: Int?, localChanges: Bool = false,
                commit: String? = nil, branch: String? = nil, treeHash: String? = nil) {
        self.release = release
        self.commitsAfter = commitsAfter
        self.localChanges = localChanges
        self.commit = commit
        self.branch = branch
        self.treeHash = treeHash
    }

    /// Read from the running bundle's Info.plist.
    public static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let commits = (info["MABuildCommitsAfter"] as? NSNumber)?.intValue
        return BuildInfo(release: UpdateChecker.installedVersion,
                         commitsAfter: commits,
                         localChanges: (info["MABuildLocalChanges"] as? NSNumber)?.boolValue ?? false,
                         commit: (info["MABuildCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                         branch: (info["MABuildBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                         treeHash: (info["MABuildTreeHash"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Newer than the release it is named after: commits since its tag or uncommitted changes. A build made
    /// from a git clone with no release tag in reach (no count) is not a release either; a copy with no
    /// stamp at all (a download) reads as one.
    public var isDevelopment: Bool {
        if localChangesUnknown { return true }          // not provably a release
        if let commitsAfter { return commitsAfter > 0 || localChanges }
        return commit != nil
    }

    /// Whether git could not say if the tree had uncommitted changes when this was built (the stamp reads
    /// "unknown"). It is never silently read as clean: the version says `.unknown`.
    public var localChangesUnknown: Bool { treeHash == "unknown" }

    // MARK: the version this copy IS

    /// The release after `release`: "2.69.2" → "2.69.3". A development build is on its way to this one.
    public static func nextPatch(after release: String) -> String {
        var parts = release.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        parts[2] += 1
        return parts.prefix(3).map(String.init).joined(separator: ".")
    }

    /// The version of a build that is not exactly a release (semantic versioning): the next patch after the
    /// release, `-dev.<commits since the release tag>`, then build metadata `+<short commit>` and `.local`
    /// when the tree had uncommitted changes. "2.69.3-dev.42+8e2c9b0.local". Without a count (no tag in
    /// reach) it is `-dev`. nil for a release: exactly the tag with a clean tree, or a copy with no stamp.
    /// By semantic-versioning precedence 2.69.2 < 2.69.3-dev.42 < 2.69.3, so a development copy is never
    /// offered the release it is already past and is offered the next real one.
    public var developmentVersion: String? {
        guard isDevelopment else { return nil }
        var text = Self.nextPatch(after: release) + "-dev" + (commitsAfter.map { ".\($0)" } ?? "")
        let metadata = [commit.map { String($0.prefix(7)) },
                        localChangesUnknown ? "unknown" : (localChanges ? "local" : nil)].compactMap { $0 }
        if !metadata.isEmpty { text += "+" + metadata.joined(separator: ".") }
        return text
    }

    /// The one version string of this copy, every surface reads it: `developmentVersion`, else the release.
    /// `app/build.sh` stamps it as `MABuildVersion` by asking this property (`agent-runner --build-version`);
    /// `CFBundleShortVersionString` stays the plain release number macOS needs.
    public var version: String { developmentVersion ?? release }

    /// The same without the build metadata, for narrow places (the sidebar): "2.69.3-dev.42".
    public var shortVersion: String { developmentVersion.map { String($0.split(separator: "+")[0]) } ?? release }

    /// "v2.68.1", or "v2.69.3-dev.42+8e2c9b0.local · Dev Build" for a development build. A development
    /// build never shows the release's number as its own (owner, 2026-11-13): the version says what it is.
    /// What a person can use is in What's New, under "In This Build — Not Yet Released".
    public var versionText: String {
        "v\(version)" + (isDevelopment ? " · \(Names.State.developmentBuild)" : "")
    }

    /// The same with the short version, for the menu-bar footer.
    public var shortVersionText: String {
        "v\(shortVersion)" + (isDevelopment ? " · \(Names.State.developmentBuild)" : "")
    }

    /// "Version 2.69.3-dev.42", for the sidebar (the full one is its hover). The state sits beside it as
    /// its own short label, so this line never grows past that.
    public var sidebarText: String { "Version \(shortVersion)" }

    /// The state line when nothing newer than this build has been published.
    /// `latest` is the newest published release, when a check has answered.
    public func developmentSentence(latest: String?) -> String {
        let named = "v\(latest ?? release)"
        if let commitsAfter, commitsAfter > 0 {
            return "This is a development build, newer than the latest release (\(named))."
        }
        return "This build has changes that are not in the latest release (\(named))."
    }
}
