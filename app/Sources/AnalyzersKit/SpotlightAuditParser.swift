import Foundation

/// Parsed spotlight-audit run: indexing status, the stuck-vs-progressing
/// verdict, and dev-directory exposure with per-item fence state. Unlike the
/// tabular login-items/storage-clean logs, this script is mostly prose
/// (status readouts + guidance paragraphs), so only well-anchored lines are
/// pulled into fields — everything else per section falls through to a raw
/// block instead of being dropped, the same "degrade honestly" approach
/// StorageCleanParser uses for third-party passthrough output.
public struct SpotlightExposureItem: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable, CaseIterable {
        case dry = "DRY"
        case fenced = "FENCED"
    }

    public let status: Status
    public let sizeBytes: Int64
    public let path: String
    public var id: String { path + status.rawValue }

    /// First path segment after "Projects/" — same grouping key the
    /// storage-clean parser uses, so a project's Spotlight exposure reads
    /// next to its cache exposure.
    public var project: String {
        if let range = path.range(of: "Projects/") {
            let tail = path[range.upperBound...]
            return String(tail.split(separator: "/").first ?? "other")
        }
        return (path as NSString).deletingLastPathComponent
            .components(separatedBy: "/").last ?? "other"
    }

    /// Last path component keys the icon (node_modules, .next, dist…).
    public var cacheKind: String { (path as NSString).lastPathComponent }
}

public struct SpotlightAuditRun: Sendable {
    public enum Verdict: String, Sendable, CaseIterable {
        case progressing = "PROGRESSING"
        case idleOrComplete = "IDLE OR COMPLETE"
        case notRunning = "NOT RUNNING"
        case unknown = "UNKNOWN"
    }

    public let header: String
    public let dryRun: Bool

    // section 1 — indexing status
    public let indexingLine: String?       // "Indexing enabled." / "...disabled."
    public let mdsLine: String?            // "N processes, M MB resident"
    public let recentUpdateLine: String?
    public let statusRaw: [String]         // whatever else section 1 said

    // section 2 — stuck-vs-progressing verdict
    public let verdict: Verdict
    public let verdictDetail: String?      // text right after "Verdict:"
    public let deepCheckCommand: String?   // the manual `log stream` command
    public let rebuildCommand: String?     // the ONE correct `mdutil -E` command
    public let verdictRaw: [String]

    // section 3 — dev-directory exposure
    public let exposureRoots: String?
    public let exposureItems: [SpotlightExposureItem]
    public let fencedCount: Int
    public let unfencedCount: Int
    public let unfencedBulkText: String?   // e.g. "13.9 GB", already formatted
    public let applyHint: String?

    /// The closing DONE / DRY-RUN line, recovered from the run's lines.
    public let summary: String?

    public var dryItems: [SpotlightExposureItem] { exposureItems.filter { $0.status == .dry } }
    public var fencedItems: [SpotlightExposureItem] { exposureItems.filter { $0.status == .fenced } }
    public var unfencedBulkBytes: Int64? { unfencedBulkText.flatMap(ByteSize.parse) }
}

public enum SpotlightAuditParser {

    public static func parse(runHeader: String, lines: [String]) -> SpotlightAuditRun {
        enum Zone { case status, verdict, exposure, other }
        var zone: Zone = .other

        var indexingLine: String?
        var mdsLine: String?
        var recentUpdateLine: String?
        var statusRaw: [String] = []

        var verdict: SpotlightAuditRun.Verdict = .unknown
        var verdictDetail: String?
        var deepCheckCommand: String?
        var rebuildCommand: String?
        var verdictRaw: [String] = []

        var exposureRoots: String?
        var items: [SpotlightExposureItem] = []
        var fencedCount = 0
        var unfencedCount = 0
        var unfencedBulkText: String?
        var applyHint: String?

        var summary: String?

        for line in lines {
            if line.hasPrefix("### ") {
                let title = String(line.dropFirst(4))
                if title.contains("Indexing status") {
                    zone = .status
                } else if title.lowercased().contains("stuck or progressing") {
                    zone = .verdict
                } else if title.lowercased().contains("dev-directory") {
                    zone = .exposure
                    if let open = title.range(of: "(roots: "),
                       let close = title.range(of: ")", range: open.upperBound..<title.endIndex) {
                        exposureRoots = String(title[open.upperBound..<close.lowerBound])
                    }
                } else {
                    zone = .other
                }
                continue
            }

            // top-level, zone-independent — the closing summary line, on the
            // rare occasion it survives inside the same block as the body.
            if line.hasPrefix("DRY RUN —") || line.hasPrefix("DONE —") {
                summary = line
                continue
            }

            switch zone {
            case .status:
                if line.hasPrefix("mds/mdworker now:") {
                    mdsLine = String(line.dropFirst("mds/mdworker now:".count))
                        .trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("recent update:") {
                    recentUpdateLine = String(line.dropFirst("recent update:".count))
                        .trimmingCharacters(in: .whitespaces)
                } else if line.lowercased().contains("indexing enabled")
                            || line.lowercased().contains("indexing disabled") {
                    indexingLine = line
                } else if line != "/:" {
                    statusRaw.append(line)
                }

            case .verdict:
                if line.hasPrefix("Verdict:") {
                    let rest = String(line.dropFirst("Verdict:".count))
                        .trimmingCharacters(in: .whitespaces)
                    verdictDetail = rest
                    if rest.hasPrefix("PROGRESSING") { verdict = .progressing }
                    else if rest.hasPrefix("IDLE") { verdict = .idleOrComplete }
                    else { verdict = .unknown }
                } else if line.contains("not running — no active indexing") {
                    verdict = .notRunning
                    verdictDetail = line
                } else if line.hasPrefix("sudo log stream") {
                    deepCheckCommand = line
                } else if line.hasPrefix("sudo mdutil -E") {
                    rebuildCommand = line
                } else {
                    verdictRaw.append(line)
                }

            case .exposure:
                if line.hasPrefix("["), let close = line.firstIndex(of: "]"),
                   let status = SpotlightExposureItem.Status(
                       rawValue: String(line[line.index(after: line.startIndex)..<close])) {
                    let rest = String(line[line.index(after: close)...])
                        .trimmingCharacters(in: .whitespaces)
                    if let sizeRange = rest.range(of: #"^~?[\d.]+ [KMGT]B\s+"#,
                                                  options: .regularExpression),
                       let bytes = ByteSize.parse(
                        String(rest[sizeRange]).trimmingCharacters(in: .whitespaces)) {
                        let path = String(rest[sizeRange.upperBound...])
                        items.append(SpotlightExposureItem(status: status, sizeBytes: bytes, path: path))
                    }
                } else if line.hasPrefix("Already fenced:") {
                    // "Already fenced: N  |  Unfenced: M  |  Unfenced bulk: X.X GB"
                    for part in line.split(separator: "|").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                        if part.hasPrefix("Already fenced:") {
                            fencedCount = Int(part.dropFirst("Already fenced:".count)
                                .trimmingCharacters(in: .whitespaces)) ?? 0
                        } else if part.hasPrefix("Unfenced bulk:") {
                            unfencedBulkText = String(part.dropFirst("Unfenced bulk:".count))
                                .trimmingCharacters(in: .whitespaces)
                        } else if part.hasPrefix("Unfenced:") {
                            unfencedCount = Int(part.dropFirst("Unfenced:".count)
                                .trimmingCharacters(in: .whitespaces)) ?? 0
                        }
                    }
                } else if line.hasPrefix("Re-run with --apply") {
                    applyHint = line
                }

            case .other:
                break
            }
        }

        return SpotlightAuditRun(
            header: runHeader,
            dryRun: runHeader.contains("DRY RUN"),
            indexingLine: indexingLine, mdsLine: mdsLine, recentUpdateLine: recentUpdateLine,
            statusRaw: statusRaw,
            verdict: verdict, verdictDetail: verdictDetail,
            deepCheckCommand: deepCheckCommand, rebuildCommand: rebuildCommand,
            verdictRaw: verdictRaw,
            exposureRoots: exposureRoots, exposureItems: items,
            fencedCount: fencedCount, unfencedCount: unfencedCount,
            unfencedBulkText: unfencedBulkText, applyHint: applyHint,
            summary: summary)
    }
}
