import Foundation

/// Parsed storage auto-clean run: sized path items (the story of this log is
/// the numbers — 26.7 GB entries buried between 4 KB ones), third-party
/// passthrough kept raw, Time Machine note, and the freed summary.
public struct StoragePathItem: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case dry = "DRY"
        case deleted = "DELETED"
        case trashed = "TRASHED"     // janitor: moved to Trash, recoverable
        case failed = "FAILED"
    }

    public enum Section: String, Sendable {
        case buildCaches = "Build Caches"
        case nodeModules = "node_modules"
    }

    public let status: Status
    public let sizeBytes: Int64
    public let path: String
    public let section: Section
    public var id: String { path + status.rawValue }

    /// First path segment after "Projects/" — the project grouping key.
    public var project: String {
        if let range = path.range(of: "Projects/") {
            let tail = path[range.upperBound...]
            return String(tail.split(separator: "/").first ?? "other")
        }
        return (path as NSString).deletingLastPathComponent
            .components(separatedBy: "/").last ?? "other"
    }

    /// Last path component keys the icon (.next, .turbo, node_modules, dist…).
    public var cacheKind: String { (path as NSString).lastPathComponent }
}

public struct StorageCleanRun: Sendable {
    public let header: String
    public let mode: String
    public let dryRun: Bool
    public let items: [StoragePathItem]
    public let activeRepoNote: String?
    public let packageManagerRaw: [String]
    public let dockerRaw: [String]
    public let tmNote: String?
    public let summary: String?
    public let freeSpaceAfter: String?
}

public enum StorageCleanParser {

    public static func parse(runHeader: String, lines: [String]) -> StorageCleanRun {
        var items: [StoragePathItem] = []
        var pmRaw: [String] = []
        var dockerRaw: [String] = []
        var tmNote: String?
        var activeRepoNote: String?
        var summary: String?
        var freeSpace: String?

        enum Zone { case caches, nodeModules, packageManagers, docker, timeMachine, other }
        var zone: Zone = .other

        for line in lines {
            if line.hasPrefix("### ") {
                let title = line.lowercased()
                if title.contains("node_modules") { zone = .nodeModules }
                else if title.contains("package-manager") { zone = .packageManagers }
                else if title.contains("docker") { zone = .docker }
                else if title.contains("time machine") { zone = .timeMachine }
                else if title.contains("cache") { zone = .caches }
                else { zone = .other }
                continue
            }
            if line.hasPrefix("DRY RUN —") || line.hasPrefix("DONE —") { summary = line; continue }
            if line.hasPrefix("Free space now:") {
                freeSpace = String(line.dropFirst(15)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("(kept node_modules") { activeRepoNote = line; continue }

            // sized path item: "[DRY]  2.0 GB  /Users/…/.next"
            if line.hasPrefix("["),
               let close = line.firstIndex(of: "]"),
               let status = StoragePathItem.Status(
                   rawValue: String(line[line.index(after: line.startIndex)..<close])) {
                let rest = String(line[line.index(after: close)...])
                    .trimmingCharacters(in: .whitespaces)
                // leading "<num> <unit>  <path>"
                if let sizeRange = rest.range(of: #"^~?[\d.]+ [KMGT]B\s+"#,
                                              options: .regularExpression),
                   let bytes = ByteSize.parse(String(rest[sizeRange]).trimmingCharacters(in: .whitespaces)) {
                    let path = String(rest[sizeRange.upperBound...])
                    items.append(StoragePathItem(
                        status: status, sizeBytes: bytes, path: path,
                        section: zone == .nodeModules ? .nodeModules : .buildCaches))
                    continue
                }
                // non-sized bracketed lines in passthrough zones fall through
            }
            switch zone {
            case .packageManagers: if !line.isEmpty { pmRaw.append(line) }
            case .docker: if !line.isEmpty { dockerRaw.append(line) }
            case .timeMachine:
                if !line.isEmpty { tmNote = tmNote.map { "\($0) \(line)" } ?? line }
            default: break
            }
        }

        var mode = "daily"
        if let range = runHeader.range(of: #"mode=(\w+)"#, options: .regularExpression) {
            mode = String(runHeader[range].dropFirst(5))
        }
        return StorageCleanRun(header: runHeader, mode: mode,
                               dryRun: runHeader.contains("DRY RUN"),
                               items: items, activeRepoNote: activeRepoNote,
                               packageManagerRaw: pmRaw, dockerRaw: dockerRaw,
                               tmNote: tmNote, summary: summary,
                               freeSpaceAfter: freeSpace)
    }
}
