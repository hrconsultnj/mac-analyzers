import Foundation

/// Every run in a block log, for totals over a period.
///
/// `LogParser.runs(for:)` reads the last 256 KB and keeps the newest 20 runs:
/// the right size for a list, the wrong one for a 30-day sum, because a log that
/// is previewed every few minutes pushes the runs that freed space out of both
/// limits within a day. The grouping below is the same as `LogParser`'s block
/// parse (a short block containing "|" is a banner; a banner-less block closes
/// the run above); it is a separate copy only so this file adds to `LogParser`
/// without editing it, and the two should become one.
extension LogParser {

    /// Newest first, no window, no cap. Day-style logs (the guard) have no
    /// block structure and read as `runs(for:)` does.
    public static func allRuns(for kind: EngineLog) -> [LogRun] {
        guard let url = kind.url,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return [] }
        guard text.contains("====") else { return runs(for: kind) }

        var blocks: [[String]] = []
        var current: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.allSatisfy({ $0 == "=" }) {
                if !current.isEmpty { blocks.append(current); current = [] }
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { blocks.append(current) }

        var result: [LogRun] = []
        var pendingHeader: String?
        for block in blocks {
            if block.count <= 3, let first = block.first, first.contains("|") {
                pendingHeader = block.joined(separator: " · ")
                continue
            }
            if pendingHeader == nil, let last = result.last {
                result[result.count - 1] = LogRun(id: last.id, header: last.header, lines: last.lines + block)
                continue
            }
            let header = pendingHeader ?? block.first ?? "Run"
            let body = pendingHeader == nil ? Array(block.dropFirst()) : block
            result.append(LogRun(id: result.count, header: header, lines: body))
            pendingHeader = nil
        }
        return result.reversed()
    }
}
