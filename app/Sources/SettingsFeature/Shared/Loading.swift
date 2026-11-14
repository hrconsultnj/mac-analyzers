import AnalyzersKit
import Foundation
import SwiftUI

/// Every pane's load goes through the shared query cache: serialized (one
/// expensive producer at a time), deduped by key, and served from a short TTL so
/// re-entering a pane or a refresh tick costs nothing.
///
/// The `key` is REQUIRED and carries everything the load depends on (a period, a
/// process, a channel): a key that names only the call site answers a second request
/// with different inputs, made within the TTL, with the first one's data. That
/// was a bug on Trends (every period), the Dossier (every process) and Update (every
/// channel) before the key stopped having a default.
func detachedLoad<T: Sendable>(_ work: @escaping @Sendable () -> T,
                               ttl: TimeInterval = 3,
                               key: String,
                               assign: @escaping @MainActor (T) -> Void) {
    Task {
        guard let value = await LoadCoordinator.shared.value(key: key, ttl: ttl, produce: work),
              !Task.isCancelled else { return }
        await MainActor.run { assign(value) }
    }
}

/// Same work, awaited by the caller — so a pane's load runs inside SwiftUI's
/// `.task`, which cancels it when the pane goes away. The fire-and-forget
/// version above starts an unowned Task: leave a pane mid-load and it keeps
/// reading the process table and the logs for a screen nobody is looking at,
/// while the pane you switched TO queues behind it. That is what made rapid
/// sidebar clicking feel stuck.
@MainActor
func awaitLoad<T: Sendable>(_ work: @escaping @Sendable () -> T,
                            ttl: TimeInterval = 3,
                            key: String,
                            assign: @MainActor (T) -> Void) async {
    guard let value = await LoadCoordinator.shared.value(key: key, ttl: ttl, produce: work),
          !Task.isCancelled else { return }
    assign(value)
}
