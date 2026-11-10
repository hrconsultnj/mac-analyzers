import Foundation

/// Everything that can be pushed on a section's stack. The cases are fixed
/// here; each payload enum belongs to the group that owns its screens and is
/// declared in that group's file, so a track adds destinations without
/// touching this one.
///
/// Payloads are identifiers, never models: a route has to survive a restart
/// (`Codable`) and compare cheaply (`Hashable`) for the stack to diff it.
enum Route: Hashable, Codable {
    case memory(MemoryRoute)
    case storage(StorageRoute)
    case system(SystemRoute)
    case history(HistoryRoute)
    case app(AppRoute)
    /// A tracked job, by id. Its screen arrives with Activity.
    case job(UUID)
}
