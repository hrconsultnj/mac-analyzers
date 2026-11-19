import Foundation

/// What "Scan Everything" on Overview queues, in order. Pure: it reads nothing and starts nothing.
///
/// The slow reports come first, so the previews a person reviews finish last, inside
/// `JobStore.reviewWindow`. The store runs one job at a time, so the memory-heavy scans never overlap.
/// Every preview carries the options its own screen starts with (`JobOptions()` for all of them but Old
/// Recordings, whose days are a setting), so Apply on that screen still works on what the scan found.
/// Nothing here can change the Mac: the kinds are reports and previews, never an apply, an install or an eject.
public enum ScanPlan {

    /// The reports, which write files and change nothing else.
    static let reports: [JobKind] = [.storageReport, .memoryReport, .networkSnapshot]

    /// The previews, in the order they run; the two memory cleanups are last because what they list changes fastest.
    static let previews: [JobKind] = [.spotlight, .unusedApps, .recordings, .storageClean, .janitor, .tempClean,
                                      .tmReclaim, .loginItems, .memoryClean, .reclaim]

    /// The requests, oldest first. Old Recordings is left out when `storage` has no recording source switched on,
    /// the same test its screen uses; Login & Startup Items is left out when `includeLoginItems` is false so a batch
    /// started from Overview never blocks on an unanswered System Events permission prompt.
    public static func requests(storage: StorageTunables, includeLoginItems: Bool = true) -> [JobRequest] {
        reports.map { JobRequest(kind: $0, intent: .run) }
            + previews.compactMap { kind in
                switch kind {
                case .recordings:
                    storage.hasRecordingSources
                        ? JobRequest(kind: kind, intent: .preview, options: JobOptions(recordingsDays: storage.recordingsDays))
                        : nil
                case .loginItems:
                    includeLoginItems ? JobRequest(kind: kind, intent: .preview) : nil
                default:
                    JobRequest(kind: kind, intent: .preview)
                }
            }
    }
}
