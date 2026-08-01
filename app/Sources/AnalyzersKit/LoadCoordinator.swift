import Foundation

/// The app's query layer — the SwiftUI answer to a request cache.
///
/// Every pane's data comes from expensive, uninterruptible work: forking
/// `ps`, sweeping every pid for rusage, parsing whole logs. Firing those
/// per view, per appear, unbounded, meant rapid navigation stacked N
/// concurrent sweeps and the UI stopped answering clicks.
///
/// Three properties fix that, and they are exactly the ones a query cache
/// gives you:
///   1. SERIALIZED — actor isolation runs one producer at a time, so ten
///      fast clicks cost one sweep at a time instead of ten at once.
///   2. DEDUPED + CACHED — a key that was produced within its TTL returns
///      instantly, so re-entering a pane (or a 5s refresh tick) is free.
///   3. KEYED PER CALL SITE — callers get a key for free from #fileID and
///      #line, so panes never collide or invalidate each other.
public actor LoadCoordinator {

    public static let shared = LoadCoordinator()

    private var cache: [String: (stamp: Date, value: any Sendable)] = [:]

    /// Fresh-enough cached value, else produce it here (on the actor, off
    /// the main thread, one at a time). `nil` means the caller was cancelled
    /// while it waited — the pane it belonged to is gone.
    public func value<T: Sendable>(key: String, ttl: TimeInterval,
                                   produce: @Sendable () -> T) -> T? {
        if let hit = cache[key], Date().timeIntervalSince(hit.stamp) < ttl,
           let typed = hit.value as? T {
            return typed
        }
        // Callers queue behind whoever is producing. Click through four panes
        // quickly and the last one used to wait out three sweeps for screens
        // already off-stage; now the abandoned ones simply never run.
        guard !Task.isCancelled else { return nil }
        let fresh = produce()
        cache[key] = (Date(), fresh)
        return fresh
    }

    /// Drop everything (used after an action changes the world — an apply,
    /// a restore — so the next read is genuinely fresh).
    public func invalidateAll() {
        cache.removeAll()
    }
}
