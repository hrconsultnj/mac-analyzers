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

    /// Reads from the end of the file in chunks that double, and looks at each byte ONCE.
    ///
    /// A banner that matches is looked for only in the part read since the last pass: if an older pass had held
    /// one, it would have returned. What is kept between passes is small: the front of what was read that is not a
    /// whole line yet (`pending`, completed by the next, older chunk, so a banner split at a chunk edge is still
    /// whole when it is looked at), and the lines from the start of what has been scanned up to its first banner
    /// (`tail`), which is where the block of a banner found in the new part ends. The first version rebuilt and
    /// re-split the whole buffer on every pass, scanning a log of 34 MB about twice over before refusing it.
    private static func search(in url: URL, reach: Int, firstChunk: Int,
                               pick: ([String], [Int]) -> Int?) -> Found {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .notFound }
        defer { try? handle.close() }
        // The size is taken once: bytes a writer appends while this reads are
        // not part of the read, so a growing log cannot move the ground.
        guard let size = try? handle.seekToEnd(), size > 0 else { return .notFound }
        var start = size
        var step = UInt64(max(firstChunk, 4096))
        var totalRead = 0
        var pending = Data()
        var tail: [String] = []
        var first = true
        while true {
            let take = min(step, start)
            start -= take
            guard (try? handle.seek(toOffset: start)) != nil,
                  let chunk = try? handle.read(upToCount: Int(take)) else { return .notFound }
            totalRead += chunk.count

            // whole lines only: drop the cut-off first line unless this reaches the start of the file, and a last
            // line a writer had not finished (only the end of the file has one)
            let region = chunk + pending
            var from = region.startIndex
            var dropped = 0
            if start > 0 {
                if let newline = region.firstIndex(of: 10) { from = region.index(after: newline) } else { from = region.endIndex }
                dropped = region.distance(from: region.startIndex, to: from)
            }
            pending = Data(region[region.startIndex..<from])
            var upto = region.endIndex
            if first, region.last != 10, let lastNewline = region.lastIndex(of: 10) { upto = region.index(after: lastNewline) }
            first = false

            let text = String(decoding: region[from..<max(from, upto)], as: UTF8.self)
            var lines: [String] = []
            var offsets: [UInt64] = []
            var position = start + UInt64(dropped)
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { lines.append(trimmed); offsets.append(position) }
                position += UInt64(raw.utf8.count) + 1
            }
            let banners = lines.indices.filter { RunMatcher.banner(in: lines[$0]) != nil }
            if let index = pick(lines, banners) {
                // a banner is only trusted when the whole block after it is in hand, which it is: what was read
                // runs to the end of the file, and the lines past this part are `tail`, up to the next banner
                let block: [String]
                if let next = banners.first(where: { $0 > index }) {
                    block = Array(lines[(index + 1)..<next])
                } else {
                    block = Array(lines[(index + 1)...]) + tail
                }
                return .block(Block(banner: lines[index], lines: block, offset: offsets[index]))
            }
            if let firstBanner = banners.first { tail = Array(lines[..<firstBanner]) } else { tail = lines + tail }
            if start == 0 { return .notFound }
            if totalRead >= reach { return .tooLarge }
            step = min(step * 2, UInt64(reach - totalRead))
        }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
