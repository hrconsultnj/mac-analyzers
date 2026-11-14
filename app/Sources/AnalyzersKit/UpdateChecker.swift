import Foundation

/// Version awareness: installed (Info.plist, injected from VERSION at build
/// time) vs the latest GitHub release. Network use is one public GET to the
/// releases API, cached for 6 hours — nothing about the machine is sent.
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
    /// A cached value OLDER than the installed build is nonsense (local
    /// builds outrun the cache) — treated as stale and refetched.
    public static func latestVersion(force: Bool = false) async -> String? {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: "updateCheckAt")
        if !force,
           Date().timeIntervalSince1970 - lastCheck < 6 * 3600,
           let cached = defaults.string(forKey: "updateLatest"),
           !isNewer(BuildInfo.current.version, than: cached) {
            return cached
        }
        guard let url = URL(string: "https://api.github.com/repos/hrconsultnj/mac-analyzers/releases/latest"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            return defaults.string(forKey: "updateLatest")   // offline → last known
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        defaults.set(version, forKey: "updateLatest")
        defaults.set(Date().timeIntervalSince1970, forKey: "updateCheckAt")
        return version
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

    // MARK: - Beta: the newest commit on `development`

    private static let repository = "hrconsultnj/mac-analyzers"

    /// Where GitHub's `development` stands against the commit this copy was built from: one public GET of
    /// the compare endpoint, cached for 6 hours per installed commit unless forced. Falls back to the last
    /// answer for that commit when it cannot be read; nil when there is none (offline).
    public static func betaCompare(installedCommit: String, force: Bool = false) async -> BetaCompare? {
        let defaults = UserDefaults.standard
        let cached = defaults.data(forKey: "updateBetaCompare")
            .flatMap { try? JSONDecoder().decode(CachedCompare.self, from: $0) }
            .flatMap { $0.commit == installedCommit ? $0 : nil }
        if !force, let cached, Date().timeIntervalSince1970 - cached.at < 6 * 3600 { return cached.compare }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/compare/\(installedCommit)...development"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse
        else { return cached?.compare }
        var result: BetaCompare?
        if http.statusCode == 403 || http.statusCode == 429 {
            // GitHub is limiting this network: not "offline", and not worth caching
            return cached?.compare ?? BetaCompare(status: "rateLimited", aheadBy: 0)
        }
        if http.statusCode == 404 || http.statusCode == 422 {
            result = BetaCompare(status: "missing", aheadBy: 0)        // GitHub does not know this commit
        } else if http.statusCode == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String {
            var newest: String?
            if let last = (json["commits"] as? [[String: Any]])?.last,
               let sha = last["sha"] as? String, let commit = last["commit"] as? [String: Any] {
                let line = (commit["message"] as? String)?.split(separator: "\n").first.map(String.init) ?? ""
                newest = "\(sha.prefix(7)) · \(line)"
            }
            result = BetaCompare(status: status, aheadBy: json["ahead_by"] as? Int ?? 0, newest: newest)
        }
        guard let result else { return cached?.compare }
        if let encoded = try? JSONEncoder().encode(CachedCompare(commit: installedCommit, at: Date().timeIntervalSince1970, compare: result)) {
            defaults.set(encoded, forKey: "updateBetaCompare")
        }
        return result
    }

    private struct CachedCompare: Codable { var commit: String; var at: Double; var compare: BetaCompare }

    /// The changelog on the `development` branch: where the Beta channel's release notes come from (its
    /// "## Next" section). Cached for the same 6 hours; the last copy when it cannot be read.
    public static func betaChangelog(force: Bool = false) async -> String? {
        let defaults = UserDefaults.standard
        let at = defaults.double(forKey: "updateBetaChangelogAt")
        if !force, Date().timeIntervalSince1970 - at < 6 * 3600, let cached = defaults.string(forKey: "updateBetaChangelog") {
            return cached
        }
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repository)/development/CHANGELOG.md"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return defaults.string(forKey: "updateBetaChangelog") }
        defaults.set(text, forKey: "updateBetaChangelog")
        defaults.set(Date().timeIntervalSince1970, forKey: "updateBetaChangelogAt")
        return text
    }
}
