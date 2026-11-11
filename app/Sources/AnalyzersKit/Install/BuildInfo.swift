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

    public init(release: String, commitsAfter: Int?, localChanges: Bool = false) {
        self.release = release
        self.commitsAfter = commitsAfter
        self.localChanges = localChanges
    }

    /// Read from the running bundle's Info.plist.
    public static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let commits = (info["MABuildCommitsAfter"] as? NSNumber)?.intValue
        return BuildInfo(release: UpdateChecker.installedVersion,
                         commitsAfter: commits,
                         localChanges: (info["MABuildLocalChanges"] as? NSNumber)?.boolValue ?? false)
    }

    /// Newer than the release it is named after.
    public var isDevelopment: Bool {
        guard let commitsAfter else { return false }
        return commitsAfter > 0 || localChanges
    }

    /// "v2.68.1", or "v2.68.1 · Dev Build" for a development build.
    ///
    /// The number of commits since the release is deliberately NOT shown: it
    /// is a developer's measure and means nothing to someone using the app
    /// (owner, 2026-11-10). What a person can use is in What's New, under
    /// "In This Build — Not Yet Released". The count stays in the stamp and
    /// in `agent-runner --probe-build`.
    public var versionText: String {
        "v\(release)" + (isDevelopment ? " · \(Names.State.developmentBuild)" : "")
    }

    /// "Version 2.68.1", for the sidebar. The state sits beside it as its own
    /// short label, so this line never grows.
    public var sidebarText: String { "Version \(release)" }

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
