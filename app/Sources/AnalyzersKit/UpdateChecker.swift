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
           !isNewer(installedVersion, than: cached) {
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

    /// Numeric semver comparison ("2.10.0" beats "2.9.0" — string compare lies).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
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
