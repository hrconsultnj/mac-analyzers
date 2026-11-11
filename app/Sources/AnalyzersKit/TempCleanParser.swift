import Foundation

/// Parsed temp-clean run: the overview numbers, disk images mounted inside
/// temp folders, and every row the engine classified — ready to clear, left
/// alone (and why), or sized-only (agent history, settings, macOS-managed
/// areas). The engine's "↳" lines ride along verbatim as `details`, the same
/// degrade-honestly approach SpotlightAuditParser takes with prose it can't
/// field-map.
public struct TempItem: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable, CaseIterable {
        case dry = "DRY"
        case trashed = "TRASHED"
        case deleted = "DELETED"
        case failed = "FAILED"
        case skip = "SKIP"
        case recent = "RECENT"
        case inUse = "IN USE"
        case protected = "PROTECTED"
        case notYours = "NOT YOURS"
        case keep = "KEEP"
        case system = "SYSTEM"
        case history = "HISTORY"
        case kept = "KEPT"
        case managed = "MANAGED"
    }

    public let status: Status
    public let sizeBytes: Int64
    /// A real path — or a family token ending in "*" that stands for many
    /// siblings (the engine re-derives the members; approving the token
    /// approves exactly those).
    public let path: String
    /// Where a TRASHED row went (recorded, never guessed — see UndoLedger).
    public let destination: String?
    public let section: String
    public let details: [String]

    public var id: String { section + "|" + path + "|" + status.rawValue }
    public var isGroup: Bool { path.hasSuffix("*") }

    /// "117 items" for a family row, 1 otherwise.
    public var count: Int {
        for line in details where line.hasSuffix(" items") {
            if let n = Int(line.split(separator: " ").first ?? "") { return n }
        }
        return 1
    }

    public var displayName: String {
        let last = (path as NSString).lastPathComponent
        return isGroup ? String(last.dropLast()) + "…" : last
    }

    /// The folder a family row's members live in, or the item's own parent.
    public var parentPath: String { (path as NSString).deletingLastPathComponent }

    /// Mount points this item backs — ejected first when it is cleared.
    public var ejects: [String] {
        guard let line = details.first(where: { $0.hasPrefix("backs mounted disk images") }),
              let colon = line.firstIndex(of: ":") else { return [] }
        return line[line.index(after: colon)...].split(separator: " ").map(String.init)
    }

    /// The one-line why: the first detail that isn't a count or an eject note.
    public var reason: String? {
        details.first { !$0.hasSuffix(" items") && !$0.hasPrefix("backs mounted disk images") }
    }

    public var isReady: Bool { status == .dry }
    public var wasActedOn: Bool { status == .trashed || status == .deleted }
    /// Sized for visibility only — history, settings, macOS's own areas.
    public var isSizedOnly: Bool { status == .history || status == .kept || status == .managed }
}

public struct TempMount: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case mounted = "MOUNTED"
        case ejected = "EJECTED"
        case ejectFailed = "EJECT FAILED"
    }

    public let status: Status
    public let sizeBytes: Int64
    public let mountPoint: String
    public let imagePath: String
    public let details: [String]

    public var id: String { mountPoint + status.rawValue }
    public var imageLivesInTemp: Bool { details.contains { $0.contains("image file lives in temp") } }

    /// Images mounted from files INSIDE this one — they go when it goes.
    public var alsoEjects: [String] {
        guard let line = details.first(where: { $0.hasPrefix("ejecting it also ejects:") }) else { return [] }
        return line.dropFirst("ejecting it also ejects:".count).split(separator: " ").map(String.init)
    }
}

public struct TempCleanRun: Sendable {
    public let header: String
    public let dryRun: Bool
    public let permanent: Bool

    // overview
    public let freeSpace: String?
    public let tempOnDisk: String?
    public let insideImages: String?
    public let plainDu: String?
    public let agentFolders: String?
    public let liveClaudeSessions: Int?
    public let codexRunning: Bool?
    public let claudeAppRunning: Bool?
    public let readyLine: String?
    public let rulesLine: String?
    public let selfCleanLine: String?

    public let mounts: [TempMount]
    public let items: [TempItem]
    /// Section titles in the engine's order — the pane groups by these.
    public let sections: [String]

    public let summary: String?
    public let freeSpaceAfter: String?

    public var readyItems: [TempItem] { items.filter(\.isReady) }
    public var readyBytes: Int64 { readyItems.reduce(0) { $0 + $1.sizeBytes } }
    public var actedItems: [TempItem] { items.filter(\.wasActedOn) }
    public var actedBytes: Int64 { actedItems.reduce(0) { $0 + $1.sizeBytes } }
    public var mountedNow: [TempMount] { mounts.filter { $0.status == .mounted } }
    public var insideImagesBytes: Int64? { insideImages.flatMap(ByteSize.parse) }

    public static let managedSection = "Managed by macOS"
    public static let tempSections: Set<String> = ["/tmp", "Your temp folder", "/var/tmp"]
}

public enum TempCleanParser {

    public static func parse(runHeader: String, lines: [String]) -> TempCleanRun {
        enum Zone { case overview, mounts, items, other }
        var zone: Zone = .other
        var section = ""
        var sections: [String] = []

        var freeSpace: String?, tempOnDisk: String?, insideImages: String?, plainDu: String?
        var agentFolders: String?, liveSessions: Int?, codexRunning: Bool?, claudeRunning: Bool?
        var readyLine: String?, rulesLine: String?, selfCleanLine: String?

        var mounts: [(status: TempMount.Status, bytes: Int64, mp: String, img: String, details: [String])] = []
        var items: [(status: TempItem.Status, bytes: Int64, path: String, dest: String?, section: String, details: [String])] = []
        enum Last { case none, mount, item }
        var last: Last = .none

        var summary: String?
        var freeAfter: String?

        for line in lines {
            if line.hasPrefix("### ") {
                var title = String(line.dropFirst(4))
                if let dot = title.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    title = String(title[dot.upperBound...])
                }
                last = .none
                if title == "Overview" { zone = .overview; continue }
                if title.hasPrefix("Mounted disk images") { zone = .mounts; continue }
                zone = .items
                if title.hasPrefix("AI agents — ") { title = String(title.dropFirst("AI agents — ".count)) }
                if title.hasPrefix(TempCleanRun.managedSection) { title = TempCleanRun.managedSection }
                section = title
                if !sections.contains(title) { sections.append(title) }
                continue
            }

            if line.hasPrefix("DRY RUN —") || line.hasPrefix("DONE —") {
                summary = line
                zone = .other
                continue
            }

            if line.hasPrefix("↳ ") {
                let detail = String(line.dropFirst(2))
                switch last {
                case .mount: mounts[mounts.count - 1].details.append(detail)
                case .item: items[items.count - 1].details.append(detail)
                case .none: break
                }
                continue
            }

            if zone == .overview || (zone == .other && summary != nil) {
                if line.hasPrefix("Free space now:") {
                    let value = line.dropFirst("Free space now:".count).trimmingCharacters(in: .whitespaces)
                    if zone == .overview { freeSpace = value } else { freeAfter = value }
                    continue
                }
            }

            if zone == .overview {
                for part in line.components(separatedBy: "  |  ") {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    func value(_ key: String) -> String? {
                        p.hasPrefix(key) ? p.dropFirst(key.count).trimmingCharacters(in: .whitespaces) : nil
                    }
                    if let v = value("Temp on disk:") { tempOnDisk = v }
                    else if let v = value("Inside mounted images:") { insideImages = v }
                    else if let v = value("A plain du would show:") { plainDu = v }
                    else if let v = value("AI agent folders:") { agentFolders = v }
                    else if let v = value("Live Claude Code sessions:") { liveSessions = Int(v) }
                    else if let v = value("Codex running:") { codexRunning = (v == "yes") }
                    else if let v = value("Claude app running:") { claudeRunning = (v == "yes") }
                }
                if line.hasPrefix("Ready to clear:") { readyLine = line }
                else if line.hasPrefix("Rules:") { rulesLine = String(line.dropFirst("Rules:".count)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("macOS also deletes") { selfCleanLine = line }
                continue
            }

            // "[STATUS] <size>  <rest>"
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let tag = String(line[line.index(after: line.startIndex)..<close])
            let rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard let sizeRange = rest.range(of: #"^~?[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
                  let bytes = ByteSize.parse(String(rest[sizeRange]).trimmingCharacters(in: .whitespaces))
            else { continue }
            let body = String(rest[sizeRange.upperBound...])

            // disk-image events can land in any zone (an apply ejects mid-list)
            if let mountStatus = TempMount.Status(rawValue: tag) {
                let parts = body.components(separatedBy: "  <-  ")
                let mp = parts[0].trimmingCharacters(in: .whitespaces)
                let img = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                if mountStatus != .mounted, let i = mounts.firstIndex(where: { $0.mp == mp }) {
                    mounts[i].status = mountStatus
                } else {
                    mounts.append((mountStatus, bytes, mp, img, []))
                }
                last = .mount
                continue
            }

            guard zone == .items, let status = TempItem.Status(rawValue: tag) else { continue }
            let pieces = ReceiptIdentity.split(body).text.components(separatedBy: "  ->  ")
            items.append((status, bytes,
                          pieces[0].trimmingCharacters(in: .whitespaces),
                          pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : nil,
                          section, []))
            last = .item
        }

        return TempCleanRun(
            header: runHeader,
            dryRun: runHeader.contains("DRY RUN"),
            permanent: runHeader.contains("permanent"),
            freeSpace: freeSpace, tempOnDisk: tempOnDisk, insideImages: insideImages,
            plainDu: plainDu, agentFolders: agentFolders, liveClaudeSessions: liveSessions,
            codexRunning: codexRunning, claudeAppRunning: claudeRunning,
            readyLine: readyLine, rulesLine: rulesLine, selfCleanLine: selfCleanLine,
            mounts: mounts.map {
                TempMount(status: $0.status, sizeBytes: $0.bytes, mountPoint: $0.mp,
                          imagePath: $0.img, details: $0.details)
            },
            items: items.map {
                TempItem(status: $0.status, sizeBytes: $0.bytes, path: $0.path,
                         destination: $0.dest, section: $0.section, details: $0.details)
            },
            sections: sections,
            summary: summary, freeSpaceAfter: freeAfter)
    }
}
