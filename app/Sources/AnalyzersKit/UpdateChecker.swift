import Foundation

/// Version awareness: installed (Info.plist, injected from VERSION at build
/// time) vs the latest GitHub release. Network use is one public GET to the
/// releases API, cached for 6 hours — nothing about the machine is sent.
public enum UpdateChecker {

    public static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Latest release version ("2.9.0"), cached for 6 h unless forced.
    public static func latestVersion(force: Bool = false) async -> String? {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: "updateCheckAt")
        if !force,
           Date().timeIntervalSince1970 - lastCheck < 6 * 3600,
           let cached = defaults.string(forKey: "updateLatest") {
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
}
