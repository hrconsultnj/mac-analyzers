import Foundation

/// What a deep link asks Memory Cleanup for: which of the two cleanups. Carried as the
/// one-shot request a `SectionIntent` holds. `actions:memoryClean` is Leftovers,
/// `actions:reclaim` and `log:reclaim` are Everything Now.
struct CleanupLink: Codable {
    var scopeKey: String?

    var scope: MemoryCleanupModel.Scope? { scopeKey.flatMap { MemoryCleanupModel.Scope(rawValue: $0) } }

    init(scope: MemoryCleanupModel.Scope) { scopeKey = scope.rawValue }

    init?(payload: String) {
        guard let link = try? JSONDecoder().decode(CleanupLink.self, from: Data(payload.utf8)) else { return nil }
        self = link
    }

    var payload: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
