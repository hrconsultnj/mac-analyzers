import Foundation

/// Version awareness: installed (Info.plist, injected from VERSION at build
/// time) vs the latest GitHub release. Network use is public, unauthenticated GETs to GitHub (the latest release; on
/// Beta and This Copy also the releases list, that beta's changelog and, for a Dev copy, one compare of the beta's tag
/// with the copy's commit), each cached for 6 hours — nothing about the machine is sent.
public enum UpdateChecker {

    public static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Which build this copy is: "a1b2c3d · Nov 10 at 17:05". The version
    /// alone can't say — it only moves at a release, and many builds share it.
    /// nil for a copy assembled without the build script.
    public static var installedBuild: String? {
        guard let revision = Bundle.main.object(forInfoDictionaryKey: "MABuildRevision") as? String
        else { return nil }
        let date = Bundle.main.object(forInfoDictionaryKey: "MABuildDate") as? String
        return date.map { "\(revision) · \($0)" } ?? revision
    }

    /// Latest release version ("2.9.0"), cached for 6 h unless forced.
    /// A cached value OLDER than the release number this copy is built from is nonsense (the cache predates a release the
    /// copy already carries) — treated as stale and refetched. A beta or Dev copy compares by that release number, not by
    /// its own version, so being past the latest release never makes the cache stale.
    public static func latestVersion(force: Bool = false) async -> String? {
        await latestRelease(force: force).version
    }

    /// The same, and whether GitHub answered: `reached` is false when the request failed (offline, a proxy, a limit) and
    /// `version` is only the last one known, so "Check for Updates" can say it could not reach GitHub instead of "up to date".
    /// A cached answer counts as reached.
    public static func latestRelease(force: Bool = false) async -> (version: String?, reached: Bool) {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: "updateCheckAt")
        if !force,
           Date().timeIntervalSince1970 - lastCheck < 6 * 3600,
           let cached = defaults.string(forKey: "updateLatest"),
           !isNewer(BuildInfo.current.release, than: cached) {
            return (cached, true)
        }
        guard let url = URL(string: "https://api.github.com/repos/hrconsultnj/sparehold/releases/latest"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            return (defaults.string(forKey: "updateLatest"), false)   // offline → last known
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        defaults.set(version, forKey: "updateLatest")
        defaults.set(Date().timeIntervalSince1970, forKey: "updateCheckAt")
        return (version, true)
    }

    /// Semantic-versioning precedence ("2.10.0" beats "2.9.0" — string compare lies; a prerelease is below its
    /// release: 2.69.2 < 2.69.3-dev.2 < 2.69.3-dev.10 < 2.69.3; build metadata after "+" is ignored).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = split(lhs), b = split(rhs)
        for i in 0..<max(a.core.count, b.core.count) {
            let x = i < a.core.count ? a.core[i] : 0
            let y = i < b.core.count ? b.core[i] : 0
            if x != y { return x > y ? .orderedDescending : .orderedAscending }
        }
        switch (a.pre.isEmpty, b.pre.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending          // a release is above its prereleases
        case (false, true): return .orderedAscending
        case (false, false): break
        }
        for i in 0..<min(a.pre.count, b.pre.count) {
            let x = a.pre[i], y = b.pre[i]
            if x == y { continue }
            switch (Int(x), Int(y)) {
            case let (nx?, ny?): return nx > ny ? .orderedDescending : .orderedAscending
            case (_?, nil): return .orderedAscending           // numbers sort below words
            case (nil, _?): return .orderedDescending
            default: return x > y ? .orderedDescending : .orderedAscending
            }
        }
        if a.pre.count == b.pre.count { return .orderedSame }
        return a.pre.count > b.pre.count ? .orderedDescending : .orderedAscending      // fewer identifiers sort lower
    }

    private static func split(_ version: String) -> (core: [Int], pre: [String]) {
        let withoutBuild = version.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".").compactMap { Int($0) }
        let pre = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
        return (core, pre)
    }

    // MARK: - Beta: the newest GitHub pre-release

    private static let repository = "hrconsultnj/sparehold"

    /// What GitHub's releases list says Beta can offer: one public GET, cached for 6 hours unless forced; the
    /// last answer when it cannot be read, nil when there is none (offline). `latestVersion` reads
    /// `/releases/latest`, which GitHub never fills with a pre-release, so a beta is never mistaken for a release.
    public static func betaFeed(force: Bool = false) async -> BetaFeed? {
        let defaults = UserDefaults.standard
        let cached = defaults.data(forKey: "updateBetaFeed").flatMap { try? JSONDecoder().decode(CachedFeed.self, from: $0) }
        if !force, let cached, Date().timeIntervalSince1970 - cached.at < 6 * 3600 { return cached.feed }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse
        else { return cached?.feed }
        if http.statusCode == 403 || http.statusCode == 429 {
            // GitHub is limiting this network: not "offline", and not worth caching
            return cached?.feed ?? BetaFeed(status: "rateLimited")
        }
        guard http.statusCode == 200, let feed = BetaFeed.parse(releases: data) else { return cached?.feed }
        if let encoded = try? JSONEncoder().encode(CachedFeed(at: Date().timeIntervalSince1970, feed: feed)) {
            defaults.set(encoded, forKey: "updateBetaFeed")
        }
        return feed
    }

    /// Whether `commit` (what a copy was built from) holds the beta published at `tag`: one public GET of GitHub's compare,
    /// cached for 6 hours per pair unless forced. nil when it cannot be said: offline, rate limited, or a commit GitHub
    /// does not know (local commits that were never pushed).
    public static func betaContainment(tag: String, commit: String, force: Bool = false) async -> BetaContainment? {
        let defaults = UserDefaults.standard
        let key = "updateBetaContainment.\(tag).\(commit)"
        if !force, let stored = defaults.string(forKey: key + ".at"), let at = Double(stored),
           Date().timeIntervalSince1970 - at < 6 * 3600, let answer = defaults.string(forKey: key) {
            return answer == "contains" ? .contains : .lacks
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/compare/\(tag)...\(commit)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let status = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
        else { return nil }
        let answer: BetaContainment = (status == "ahead" || status == "identical") ? .contains : .lacks
        defaults.set(answer == .contains ? "contains" : "lacks", forKey: key)
        defaults.set(String(Date().timeIntervalSince1970), forKey: key + ".at")
        return answer
    }

    private struct CachedFeed: Codable { var at: Double; var feed: BetaFeed }

    /// The changelog at a ref of the repository: where the Beta channel's release notes come from (its "## Next"
    /// section) — the newest beta's tag, or `development` when no beta is out. Cached for the same 6 hours per
    /// ref; the last copy when it cannot be read.
    public static func betaChangelog(ref: String, force: Bool = false) async -> String? {
        let defaults = UserDefaults.standard
        let refKey = defaults.string(forKey: "updateBetaChangelogRef")
        let at = defaults.double(forKey: "updateBetaChangelogAt")
        if !force, refKey == ref, Date().timeIntervalSince1970 - at < 6 * 3600, let cached = defaults.string(forKey: "updateBetaChangelog") {
            return cached
        }
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repository)/\(ref)/CHANGELOG.md"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return refKey == ref ? defaults.string(forKey: "updateBetaChangelog") : nil }
        defaults.set(text, forKey: "updateBetaChangelog")
        defaults.set(ref, forKey: "updateBetaChangelogRef")
        defaults.set(Date().timeIntervalSince1970, forKey: "updateBetaChangelogAt")
        return text
    }
}

extension BetaFeed {
    /// Reads GitHub's releases list (an array of objects with `tag_name`, `prerelease`, `draft`). A beta is a
    /// pre-release tagged exactly `vX.Y.Z-beta.N`; a release is a published non-pre-release tagged exactly
    /// `vX.Y.Z`. Anything else (drafts, other tags) is ignored. nil when the data is not a list.
    public static func parse(releases data: Data) -> BetaFeed? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var beta: String?, release: String?
        for item in list {
            guard let tag = item["tag_name"] as? String, item["draft"] as? Bool != true else { continue }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let isPre = item["prerelease"] as? Bool ?? false
            if isPre {
                guard BuildInfo.betaNumber(inTag: tag) != nil else { continue }
                if beta.map({ isNewerVersion(version, than: $0) }) ?? true { beta = version }
            } else {
                guard version.split(separator: ".").count == 3, version.split(separator: ".").allSatisfy({ Int($0) != nil }) else { continue }
                if release.map({ isNewerVersion(version, than: $0) }) ?? true { release = version }
            }
        }
        return BetaFeed(newestBeta: beta, newestRelease: release)
    }

    private static func isNewerVersion(_ a: String, than b: String) -> Bool { UpdateChecker.isNewer(a, than: b) }
}
