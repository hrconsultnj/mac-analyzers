import Foundation

/// What this copy is, as one value every surface reads: the Update screen, the sidebar, the menu footer and
/// What's New. There are three kinds, and a person reads one short name for each:
///
/// - a release, built at its tag: "2.72.0";
/// - a published beta, built at its `vX.Y.Z-beta.N` tag with a clean tree: "2.72.1 Beta" ("2.72.1 Beta 2" from
///   the second one on);
/// - anything else built from a clone, "This Copy": the version development is on, "3.2.0 Dev · 83dc530"
///   (commits after the last tag, or changes that are not committed; a trailing * marks uncommitted changes).
///
/// The full semantic-versioning string (`version`: "2.72.1-beta.2", "2.72.1-dev.12+8e2c9b0") stays inside, for
/// comparisons; `label` and the texts built on it are the only thing a person reads. `build.sh` stamps the
/// nearest release tag, the commits made since it, whether the tree had local changes and the beta tag the
/// commit sits on; a copy with no stamp (a download, or a build with no git history) reads as a release.
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
    /// The release tag the commit count was made from ("v2.69.2"). It is `v` + `release` unless that tag is
    /// not in the clone (`VERSION` bumped before the release is tagged, or a tag not fetched): then the count
    /// is from an older tag and this build is heading TO `release`, not past it. nil: not stamped.
    public let releaseTag: String?
    /// The beta tag this commit sits exactly on ("v2.72.1-beta.2"), when it is one. nil: not a published beta.
    /// Only a clean tree built at that tag is a beta (`isBeta`); with changes on top it is a Dev copy.
    public let betaTag: String?

    public init(release: String, commitsAfter: Int?, localChanges: Bool = false,
                commit: String? = nil, branch: String? = nil, treeHash: String? = nil, releaseTag: String? = nil,
                betaTag: String? = nil) {
        self.releaseTag = releaseTag
        self.betaTag = betaTag.flatMap { Self.betaNumber(inTag: $0) != nil ? $0 : nil }
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
                         treeHash: (info["MABuildTreeHash"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                         releaseTag: (info["MABuildReleaseTag"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                         betaTag: (info["MABuildBetaTag"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Newer than the release it is named after: commits since its tag or uncommitted changes. A build made
    /// from a git clone with no release tag in reach (no count) is not a release either; a copy with no
    /// stamp at all (a download) reads as one.
    public var isDevelopment: Bool {
        if isBeta { return false }                      // a published beta is pre-release, not "this copy"
        if localChangesUnknown { return true }          // not provably a release
        if let commitsAfter { return commitsAfter > 0 || localChanges }
        return commit != nil
    }

    /// Whether git could not say if the tree had uncommitted changes when this was built (the stamp reads
    /// "unknown"). It is never silently read as clean: the version says `.unknown`.
    public var localChangesUnknown: Bool { treeHash == "unknown" }

    /// A published beta: built at its beta tag, with nothing uncommitted (and git able to say so).
    public var isBeta: Bool { betaTag != nil && !localChanges && !localChangesUnknown }

    // MARK: the version this copy IS

    /// The beta number of a `vX.Y.Z-beta.N` tag; nil for any other tag.
    static func betaNumber(inTag tag: String) -> Int? {
        let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].split(separator: ".").count == 3,
              parts[0].split(separator: ".").allSatisfy({ Int($0) != nil }),
              parts[1].hasPrefix("beta."), let number = Int(parts[1].dropFirst(5)), number >= 1,
              parts[1].dropFirst(5).allSatisfy(\.isNumber)
        else { return nil }
        return number
    }

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
        // past the release only when its own tag was the one counted from; otherwise it is on its way to `release`
        // itself ("2.70.0-dev.15", below 2.70.0), so the release is still offered when it is published
        let base = releaseTag.map { $0 == "v\(release)" } ?? true ? Self.nextPatch(after: release) : release
        var text = base + "-dev" + (commitsAfter.map { ".\($0)" } ?? "")
        let metadata = [commit.map { String($0.prefix(7)) },
                        localChangesUnknown ? "unknown" : (localChanges ? "local" : nil)].compactMap { $0 }
        if !metadata.isEmpty { text += "+" + metadata.joined(separator: ".") }
        return text
    }

    /// The one version string of this copy, every surface reads it: `developmentVersion`, else the release.
    /// `app/build.sh` stamps it as `MABuildVersion` by asking this property (`agent-runner --build-version`);
    /// `CFBundleShortVersionString` stays the plain release number macOS needs.
    public var version: String {
        if isBeta, let betaTag { return String(betaTag.dropFirst()) }
        return developmentVersion ?? release
    }

    // MARK: what a person reads

    /// The short name of a version string, the one place the full string becomes words:
    /// "2.72.0" → "2.72.0"; "2.72.1-beta.1" → "2.72.1 Beta"; "2.72.1-beta.2" → "2.72.1 Beta 2";
    /// "2.72.1-dev.12+8e2c9b0" → "Dev · 8e2c9b0"; with uncommitted changes (".local") "Dev · 8e2c9b0*"; when git
    /// could not say (".unknown") "Dev · 8e2c9b0?". A development version with no commit reads "Dev".
    public static func label(forVersion version: String) -> String {
        let halves = version.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let core = halves[0]
        let metadata = halves.count > 1 ? halves[1] : ""
        guard let dash = core.firstIndex(of: "-") else { return core }
        let number = String(core[..<dash])
        let pre = String(core[core.index(after: dash)...])
        if pre.hasPrefix("beta") {
            let n = pre.split(separator: ".").dropFirst().first.flatMap { Int($0) } ?? 1
            return n > 1 ? "\(number) Beta \(n)" : "\(number) Beta"
        }
        // a development version carries the number development is on (owner, 2026-11-20):
        // "3.2.0 Dev · 83dc530", then a mark for what is uncommitted — "Dev" alone said nothing
        // about which work this copy holds.
        let pieces = metadata.split(separator: ".").map(String.init)
        var text = "\(number) Dev"
        if let commit = pieces.first, !commit.isEmpty, commit != "local", commit != "unknown" {
            text += " · \(commit)"
            if pieces.contains("local") { text += "*" } else if pieces.contains("unknown") { text += "?" }
        }
        return text
    }

    /// Whether a version string is a development one: a pre-release that is not a beta ("3.2.0-dev.1").
    public static func isDevelopmentVersion(_ version: String) -> Bool {
        let core = version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? version
        guard let dash = core.firstIndex(of: "-") else { return false }
        return !core[core.index(after: dash)...].hasPrefix("beta")
    }

    /// What this copy is called: "2.72.0", "2.72.1 Beta", "Dev · 8e2c9b0".
    public var label: String { Self.label(forVersion: version) }

    /// The same as `label`; the narrow places (the About panel, the menu footer, the sidebar) read it too.
    public var shortVersion: String { label }

    /// "v3.1.0", "v2.72.1 Beta" or "3.2.0 Dev · 83dc530" — a development copy shows the number development
    /// is on (owner, 2026-11-20, superseding the 2026-11-13 ruling); what it holds is still in What's New
    /// under "In This Build — Not Yet Released".
    public var versionText: String { Self.isDevelopmentVersion(version) ? label : "v\(label)" }

    /// The menu-bar footer says the same.
    public var shortVersionText: String { versionText }

    /// "Version 2.72.0", "Version 2.72.1 Beta"; a Dev copy has no number to call a version: "Dev · 8e2c9b0". The
    /// state sits beside it as its own short label, so this line never grows past that.
    public var sidebarText: String { Self.isDevelopmentVersion(version) ? label : "Version \(label)" }

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
