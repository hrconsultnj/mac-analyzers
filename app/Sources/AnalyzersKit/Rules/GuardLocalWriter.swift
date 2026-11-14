import Foundation

/// Writes the person's changes to `rules.local.json`: only this app writes it, sparsely (a mode that differs from the plan's, a
/// limit that does, the two lists). A file it could not read is never overwritten: the change is refused with the reason, so a
/// hand-edit that went wrong is not replaced by something that looks fine.
public enum GuardLocalWriter {

    public enum Failure: Error, Equatable { case unreadable(String) }

    @discardableResult
    public static func update(_ change: (inout GuardLocalRules) -> Void, file: URL = GuardRules.localFile) -> Result<GuardLocalRules, Failure> {
        var current = GuardLocalRules.empty
        if let data = try? Data(contentsOf: file) {
            current = GuardLocalRules.parse(data)
            if let problem = current.problems.first { return .failure(.unreadable(problem)) }
        }
        change(&current)
        var object: [String: Any] = ["schema": 1]
        if !current.modes.isEmpty { object["modes"] = current.modes.mapValues(\.rawValue) }
        if !current.limits.isEmpty {
            object["limits"] = current.limits.mapValues { limit -> [String: Any] in
                var entry: [String: Any] = [:]
                if let gb = limit.gb { entry["gb"] = gb }
                if let overFor = limit.overFor { entry["overFor"] = overFor }
                return entry
            }
        }
        if !current.neverClose.isEmpty { object["neverClose"] = current.neverClose }
        if !current.mayQuit.isEmpty { object["mayQuit"] = current.mayQuit }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return .failure(.unreadable("the changes could not be written"))
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return .failure(.unreadable("the file could not be written")) }
        return .success(current)
    }

    /// Tell the guard script and the cleanups about a change to the Never Close list (they read the fallback file, not this one).
    public static func refreshFallback() {
        GuardFallbackFile.write(neverClose: GuardRules.load().local.neverClose)
    }
}
