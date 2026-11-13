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
        var start = size > window ? size - window : 0
        // A run bigger than the window (a Downloads preview prints a line per file: 6,000 screenshots are 600 KB) would
        // be read from its middle, with no banner: it was then listed under one of its own file lines, started "one
        // minute late", and its screen could not find it. The window starts at the banner of the run it falls in.
        var alignedToLine = false
        // Only a log of the block style has banners, and that is decided first and cheaply: an event log such as the
        // guard's has no rule line anywhere and was read backwards in full to find that out. The window answers it, else
        // the head of the file (a block log opens with a rule).
        if start > 0, isBlockStyle(handle, windowStart: start), let banner = bannerStart(before: start, in: handle) {
            start = banner; alignedToLine = true
        }
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd() else { return [] }
        // The window starts at a byte, which can be the middle of a multi-byte
        // character; decoding that strictly makes the whole tail nothing, so a log
        // would vanish until it grew past the offset. Start at the first whole line
        // and decode leniently.
        if start > 0, !alignedToLine, let newline = data.firstIndex(of: 10) { data = data[data.index(after: newline)...] }
        let text = String(decoding: data, as: UTF8.self)
        let lines = LogLines.lines(in: data)

        return text.contains("====") ? runBlocks(lines, includingRestores: includingRestores) : dayGroups(lines)
    }

    /// Whether this is a block log (rule lines between runs): a rule in the window that will be read, or in the first 64 KB.
    private static func isBlockStyle(_ handle: FileHandle, windowStart: UInt64) -> Bool {
        let rule = Data("====".utf8)
        for (from, length) in [(windowStart, 262_144), (UInt64(0), 65_536)] {
            guard (try? handle.seek(toOffset: from)) != nil, let chunk = try? handle.read(upToCount: length) else { continue }
            if chunk.range(of: rule) != nil { return true }
        }
        return false
    }

    /// How far back a run's banner is looked for: the same reach as `WholeRun`.
    private static let bannerReach = 32 * 1_048_576

    /// Where the banner line of the run that `offset` falls in begins: the nearest banner before it, read backwards in
    /// chunks. nil when there is none within reach (the log has no banners, or the run is bigger than the reach).
    private static func bannerStart(before offset: UInt64, in handle: FileHandle) -> UInt64? {
        var end = offset
        var read: UInt64 = 0
        while end > 0, read < UInt64(bannerReach) {
            let take = min(UInt64(262_144), end)
            let begin = end - take
            guard (try? handle.seek(toOffset: begin)) != nil, let chunk = try? handle.read(upToCount: Int(take)) else { return nil }
            read += take
            let found = LogLines.lines(in: chunk, base: begin)
            // the first line of a chunk that does not start the file may be cut; the last may run past `end`
            var index = found.lines.count - 1
            while index >= 0 {
                let cut = index == 0 && begin > 0
                if !cut, RunMatcher.banner(in: found.lines[index]) != nil {
                    // the rule line above a banner goes with it: the parser reads a log as report-style by its rules
                    if index > 0, found.lines[index - 1].allSatisfy({ $0 == "=" }) { return found.offsets[index - 1] }
                    return found.offsets[index]
                }
                index -= 1
            }
            end = begin
        }
        return nil
    }

    /// Report-style logs: runs delimited by ===== separators; a short block
    /// containing "|" is the header for the body block that follows. Headers
    /// run to 3 lines (title, settings, `input:`) — a body block never starts
    /// with a "|" line, it opens on a `### ` group.
    /// THE grouping of a block log's lines into runs, newest first, for every reader: Activity's list (`limit` 20, over a
    /// window), Trends and Undo's dates (`limit` nil, the whole log). One function, so two readers never disagree about
    /// where a run begins.
    static func runBlocks(_ allLines: [String], includingRestores: Bool, limit: Int? = 20) -> [LogRun] {
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
            // a block that OPENS with a banner is a run of its own: the janitor writes a rule, the banner and the body with no
            // rule between them, so before this its second run in a window was taken for the first one's closing summary
            if pendingHeader == nil, let first = block.first, RunMatcher.banner(in: first) != nil, first.isEmpty {
                result.append(LogRun(id: result.count, header: first, lines: Array(block.dropFirst())))
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
        let newestFirst = limit.map { Array(result.reversed().prefix($0)) } ?? Array(result.reversed())
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
