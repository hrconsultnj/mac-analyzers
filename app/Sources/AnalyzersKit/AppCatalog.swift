import Foundation

/// What's installed (for app pickers) and what's running (for protected-
/// process suggestions) — so users pick from reality instead of guessing
/// names into a text field.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String
    public var id: String { path }
}

public enum AppCatalog {

    /// Apps in the standard locations, alphabetical, deduped by name.
    public static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = [
            "/Applications",
            "/System/Applications",
            AnalyzersPaths.home.appending(path: "Applications").path,
        ]
        var apps: [InstalledApp] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let full = "\(root)/\(entry)"
                if entry.hasSuffix(".app") {
                    apps.append(InstalledApp(name: String(entry.dropLast(4)), path: full))
                } else if (try? fm.contentsOfDirectory(atPath: full)) != nil {
                    // one level of vendor subfolders (e.g. /Applications/Utilities)
                    for sub in (try? fm.contentsOfDirectory(atPath: full)) ?? []
                    where sub.hasSuffix(".app") {
                        apps.append(InstalledApp(name: String(sub.dropLast(4)),
                                                 path: "\(full)/\(sub)"))
                    }
                }
            }
        }
        var seen = Set<String>()
        return apps
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Short name candidates from what's running right now — suggestions for
    /// the protected-process fragment list.
    public static func runningNameSuggestions() -> [String] {
        var seen = Set<String>()
        return LiveStats.snapshot(limit: 60, minimumMB: 64)
            .map { proc in
                let raw = proc.rawName
                if let range = raw.range(of: #"([^/]+)\.app"#, options: .regularExpression) {
                    return String(raw[range].dropLast(4))
                }
                return String(raw.split(separator: " ").first.map {
                    $0.split(separator: "/").last.map(String.init) ?? String($0)
                } ?? raw)
            }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
