import Foundation

/// When a run happened, read from its banner. Banners carry the date in
/// different places, with or without seconds; this finds it.
public enum RunDate {

    /// The banner's date and whether it is exact to the second (a minute-only
    /// banner is exact to the minute).
    public static func parse(banner: String) -> (date: Date, hasSeconds: Bool)? {
        guard let range = banner.range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?"#, options: .regularExpression)
        else { return nil }
        let text = String(banner[range])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let seconds = text.count > 16
        formatter.dateFormat = seconds ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        return formatter.date(from: text).map { ($0, seconds) }
    }

    public static func date(of banner: String) -> Date? { parse(banner: banner)?.date }

    /// False only when the banner's own date shows the run began before `start`
    /// (compared at the banner's precision, so a banner stamped 12:03 does not
    /// count as earlier than a job that began at 12:03:41). A banner with no
    /// date cannot be ruled out.
    public static func isNotBefore(banner: String, start: Date) -> Bool {
        guard let parsed = parse(banner: banner) else { return true }
        let unit: TimeInterval = parsed.hasSeconds ? 1 : 60
        let floored = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / unit).rounded(.down) * unit)
        return parsed.date >= floored
    }
}

/// One whole run of an engine log, found by its banner.
///
/// `LogParser` reads the last 256 KB of a log, which is right for listing
/// recent runs and wrong for one run bigger than that: the Downloads cleanup
/// prints a line per file, so 6,000 old screenshots make a 600 KB preview whose
/// banner is outside the window. This reads backwards from the end of the log,
/// in chunks that double, until the banner is in hand — so a banner near the
/// end (every ordinary run) costs one 256 KB read, as before — and stops at a
/// fixed reach.
///
/// Which block when banners repeat: two runs started in the same second print
/// the same banner. The job's own block is the LAST block with that banner
/// whose banner date is not before the job's start (`notBefore`).
public enum WholeRun {

    public struct Block: Sendable {
        /// The banner line, trimmed.
        public let banner: String
        /// Every line after the banner up to the next run's banner, trimmed, blanks dropped.
        public let lines: [String]
        /// Where the banner starts in the file.
        public let offset: UInt64
        /// The block as a `LogRun`, header = the banner.
        public var run: LogRun { LogRun(id: 0, header: banner, lines: lines) }
    }

    public enum Found: Sendable {
        case block(Block)
        /// The log holds no such block (or the log is unreadable).
        case notFound
        /// The banner was not within `reach` of the end of the log.
        case tooLarge
    }

    /// How far back from the end of a log to look: 32 MB.
    public static let reach = 32 * 1_048_576
    /// The first read; the same 256 KB `LogParser` reads.
    public static let firstChunk = 262_144

    /// The block whose banner is `banner` (compared with whitespace collapsed).
    /// Touches the disk: call it off the main actor.
    public static func find(banner: String, in url: URL, notBefore: Date? = nil, reach: Int = reach,
                            firstChunk: Int = firstChunk) -> Found {
        search(in: url, reach: reach, firstChunk: firstChunk) { lines, banners in
            let wanted = normalized(banner)
            return banners.last { index in
                normalized(lines[index]) == wanted
                    && (notBefore.map { RunDate.isNotBefore(banner: lines[index], start: $0) } ?? true)
            }
        }
    }

    /// The newest block that is a dry run, for a screen that shows the last preview.
    public static func newestPreview(in url: URL, reach: Int = reach) -> Found {
        search(in: url, reach: reach, firstChunk: firstChunk) { lines, banners in
            banners.last { lines[$0].contains("DRY RUN") }
        }
    }

    // MARK: - the backwards read

    private static func search(in url: URL, reach: Int, firstChunk: Int,
                               pick: ([String], [Int]) -> Int?) -> Found {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .notFound }
        defer { try? handle.close() }
        // The size is taken once: bytes a writer appends while this reads are
        // not part of the read, so a growing log cannot move the ground.
        guard let size = try? handle.seekToEnd(), size > 0 else { return .notFound }
        var start = size
        var step = UInt64(max(firstChunk, 4096))
        var buffer = Data()
        while true {
            let take = min(step, start)
            start -= take
            guard (try? handle.seek(toOffset: start)) != nil,
                  let chunk = try? handle.read(upToCount: Int(take)) else { return .notFound }
            buffer = chunk + buffer

            // whole lines only: drop the cut-off first line unless the buffer starts the file,
            // and a last line a writer had not finished
            var from = buffer.startIndex
            var lineOffset = start
            if start > 0, let newline = buffer.firstIndex(of: 10) {
                from = buffer.index(after: newline)
                lineOffset = start + UInt64(buffer.distance(from: buffer.startIndex, to: from))
            }
            var upto = buffer.endIndex
            if buffer.last != 10, let lastNewline = buffer.lastIndex(of: 10) { upto = buffer.index(after: lastNewline) }
            let text = String(decoding: buffer[from..<max(from, upto)], as: UTF8.self)
            var lines: [String] = []
            var offsets: [UInt64] = []
            var position = lineOffset
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { lines.append(trimmed); offsets.append(position) }
                position += UInt64(raw.utf8.count) + 1
            }
            let banners = lines.indices.filter { RunMatcher.banner(in: lines[$0]) != nil }
            if let index = pick(lines, banners) {
                // a banner is only trusted when the whole block after it is in hand, which
                // it is: the buffer runs to the end of the file
                let end = banners.first { $0 > index } ?? lines.endIndex
                return .block(Block(banner: lines[index], lines: Array(lines[(index + 1)..<end]),
                                    offset: offsets[index]))
            }
            if start == 0 { return .notFound }
            if buffer.count >= reach { return .tooLarge }
            step = min(step * 2, UInt64(reach - buffer.count))
        }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
