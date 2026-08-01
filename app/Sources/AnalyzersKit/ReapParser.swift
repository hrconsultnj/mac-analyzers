import Foundation

/// Shared parser for the two process-reap logs — memory auto-clean and
/// memory-reclaim. Their item shapes are ~90% identical ([STATUS] MB pid
/// description); the group names differ and only reclaim has EXEMPT rows.
public struct ReapItem: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case dry = "DRY"
        case killed = "KILLED"
        case reported = "REPORT"
        case gone = "GONE"
        case exempt = "EXEMPT"
        case quit = "QUIT"
        case skip = "SKIP"
    }

    public let status: Status
    public let mb: Int?
    public let pid: Int?
    public let description: String
    public var id: String { "\(pid ?? 0)-\(description)-\(status.rawValue)" }

    public var friendlyName: String {
        ProcessGlossary.friendlyName(for: description) ?? String(description.prefix(60))
    }
}

public struct ReapGroup: Identifiable, Sendable {
    public let title: String
    public let items: [ReapItem]
    /// Group-5-style aggregates: "4× context7-mcp — 325 MB total" (no pid,
    /// never killed — stat chips, not process cards).
    public let aggregates: [(label: String, count: Int, totalMB: Int)]
    public var id: String { title }
}

public struct ReapRun: Sendable {
    public let header: String
    public let dryRun: Bool
    public let exemptNote: String?
    public let groups: [ReapGroup]
    public let summary: String?
    public let before: String?
    public let after: String?

    public var allItems: [ReapItem] { groups.flatMap(\.items) }
}

public enum ReapParser {

    public static func parse(runHeader: String, lines: [String]) -> ReapRun {
        var groups: [ReapGroup] = []
        var currentTitle: String?
        var items: [ReapItem] = []
        var aggregates: [(String, Int, Int)] = []
        var exemptNote: String?
        var summary: String?
        var before: String?
        var after: String?

        func flushGroup() {
            if currentTitle != nil || !items.isEmpty || !aggregates.isEmpty {
                groups.append(ReapGroup(title: currentTitle ?? "Items",
                                        items: items, aggregates: aggregates))
            }
            items = []
            aggregates = []
        }

        for line in lines {
            if line.hasPrefix("### ") {
                flushGroup()
                currentTitle = String(line.dropFirst(4))
                continue
            }
            if line.hasPrefix("exempt:") {
                exemptNote = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("Before:") { before = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces); continue }
            if line.hasPrefix("After:") { after = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
            if line.hasPrefix("DRY RUN —") || line.hasPrefix("DONE —") {
                summary = line
                continue
            }
            // aggregate: "4× context7-mcp    325 MB total"
            if let match = line.range(of: #"^(\d+)× (.+?)\s{2,}(\d+) MB total$"#,
                                      options: .regularExpression) {
                let text = String(line[match])
                let comps = text.components(separatedBy: "× ")
                if let count = Int(comps[0]),
                   let tail = comps.last {
                    let tailParts = tail.components(separatedBy: "  ").filter { !$0.isEmpty }
                    let name = tailParts.first?.trimmingCharacters(in: .whitespaces) ?? tail
                    let total = Int(tail.components(separatedBy: " ")
                        .last(where: { Int($0) != nil }) ?? "") ?? 0
                    aggregates.append((name, count, total))
                }
                continue
            }
            // item: "[DRY]       30 MB  pid=95170  stale-dev (25h): next-server…"
            guard line.hasPrefix("["),
                  let close = line.firstIndex(of: "]") else { continue }
            let statusText = String(line[line.index(after: line.startIndex)..<close])
            guard let status = ReapItem.Status(rawValue: statusText) else { continue }
            var rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)

            var mb: Int?
            if let mbRange = rest.range(of: #"^(\d+) MB\s+"#, options: .regularExpression) {
                mb = Int(rest[mbRange].components(separatedBy: " ")[0])
                rest = String(rest[mbRange.upperBound...])
            }
            var pid: Int?
            if let pidRange = rest.range(of: #"pid=(\d+)\s*"#, options: .regularExpression) {
                pid = Int(rest[pidRange].dropFirst(4).trimmingCharacters(in: .whitespaces))
                rest.removeSubrange(pidRange)
            }
            items.append(ReapItem(status: status, mb: mb, pid: pid,
                                  description: rest.trimmingCharacters(in: .whitespaces)))
        }
        flushGroup()

        return ReapRun(header: runHeader,
                       dryRun: runHeader.contains("DRY RUN"),
                       exemptNote: exemptNote,
                       groups: groups.filter { !$0.items.isEmpty || !$0.aggregates.isEmpty },
                       summary: summary, before: before, after: after)
    }
}
