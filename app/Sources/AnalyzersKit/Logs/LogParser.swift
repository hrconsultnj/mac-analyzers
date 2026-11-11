import Foundation

public enum LogParser {

    /// Parse a log file into runs, newest first. A restore's own block (`RestoreBlock`) is not a
    /// run of the cleaner whose log it is written in, so it is left out unless `includingRestores`
    /// (Activity lists it as its own row); that keeps "the newest run" the cleaner's own.
    public static func runs(for kind: EngineLog, includingRestores: Bool = false) -> [LogRun] {
        kind.url.map { runs(at: $0, includingRestores: includingRestores) } ?? []
    }

    /// The same parse over any file, so a copy of a log can be read the way
    /// the real one is (the id-stability probe does this).
    public static func runs(at url: URL, includingRestores: Bool = false) -> [LogRun] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 262_144
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd() else { return [] }
        // The window starts at a byte, which can be the middle of a multi-byte
        // character; decoding that strictly makes the whole tail nothing, so a log
        // would vanish until it grew past the offset. Start at the first whole line
        // and decode leniently.
        if start > 0, let newline = data.firstIndex(of: 10) { data = data[data.index(after: newline)...] }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return text.contains("====") ? runBlocks(lines, includingRestores: includingRestores) : dayGroups(lines)
    }

    /// Report-style logs: runs delimited by ===== separators; a short block
    /// containing "|" is the header for the body block that follows. Headers
    /// run to 3 lines (title, settings, `input:`) — a body block never starts
    /// with a "|" line, it opens on a `### ` group.
    private static func runBlocks(_ allLines: [String], includingRestores: Bool) -> [LogRun] {
        // a restore's block is taken out first, so the rest parses exactly as it would without it
        let (lines, restores) = RestoreBlock.split(allLines)
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
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
                // A ====-wrapped block with no banner before it is the closing
                // summary of the run above (DONE / DRY-RUN trailer), not a run.
                result[result.count - 1] = LogRun(id: last.id, header: last.header,
                                                  lines: last.lines + block)
                continue
            }
            let header = pendingHeader ?? block.first ?? "Run"
            let body = pendingHeader == nil ? Array(block.dropFirst()) : block
            result.append(LogRun(id: result.count, header: header, lines: body))
            pendingHeader = nil
        }
        let newestFirst = Array(result.reversed().prefix(20))
        return includingRestores ? RestoreBlock.merge(restores: restores, into: newestFirst) : newestFirst
    }

    /// Event-style logs (guard): group by day, newest day first, newest line
    /// first inside the day.
    private static func dayGroups(_ lines: [String]) -> [LogRun] {
        var byDay: [(day: String, lines: [String])] = []
        for line in lines.suffix(400) {
            let day = String(line.prefix(10))
            if byDay.last?.day == day {
                byDay[byDay.count - 1].lines.append(line)
            } else {
                byDay.append((day, [line]))
            }
        }
        return byDay.reversed().enumerated().map { index, group in
            LogRun(id: index, header: group.day, lines: group.lines.reversed())
        }
    }

    public static func cleaned(_ line: String) -> String {
        var out = line
        for tag in ["[DRY]", "[KILLED]", "[QUIT]", "[DELETED]", "[EXEMPT]", "[GONE]"] {
            out = out.replacingOccurrences(of: tag, with: "")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
