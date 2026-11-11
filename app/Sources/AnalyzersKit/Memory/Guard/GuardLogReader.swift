import Foundation

/// Reads a guard log back from its end to a date, not for a fixed number of
/// lines. The guard writes a line every few seconds when something is going
/// on, so any fixed line count is a different number of days on every Mac —
/// on the one this was written on, 2,000 lines was eight days, and a "last 90
/// days" screen quietly showed eight.
///
/// Memory is bounded: the file is read in chunks from its end, a line at a
/// time, and reading stops at the cutoff or at `maxBytes`, whichever comes
/// first. When the current file does not reach the cutoff, the rotated one
/// (`guard.log.1`, what the guard keeps when the log passes 5 MB) is read too.
/// Blocking: call it off the main actor.
public enum GuardLogReader {

    public struct Reading: Sendable {
        /// Oldest first. Lines with no timestamp (a continuation of the line
        /// above) stay with it.
        public let lines: [String]
        /// The oldest timestamp read, "yyyy-MM-dd HH:mm:ss"; nil for an empty log.
        public let oldest: String?
        /// False when reading stopped at `maxBytes`, or the log is simply
        /// younger than the cutoff — `oldest` says how far back it really goes.
        public let reachedCutoff: Bool
        /// How many bytes were read.
        public let bytesRead: Int
    }

    public static let chunk = 256 * 1024
    public static let defaultMaxBytes = 16 * 1024 * 1024

    private static let timestampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// Every line stamped at or after `cutoff`, from `url` and, when needed,
    /// its rotated copy `<url>.1`.
    public static func read(_ url: URL, since cutoff: Date, maxBytes: Int = defaultMaxBytes) -> Reading {
        let cutoffText = timestampFormat.string(from: cutoff)
        var newestFirst: [String] = []        // lines in file order reversed, per file
        var oldest: String?
        var bytes = 0
        var reached = false

        for file in [url, URL(fileURLWithPath: url.path + ".1")] {
            let budget = maxBytes - bytes
            guard budget > 0 else { break }
            let part = readBackwards(file, cutoffText: cutoffText, budget: budget)
            bytes += part.bytes
            newestFirst.append(contentsOf: part.lines)
            if let first = part.oldest { oldest = first }
            if part.reachedCutoff { reached = true; break }
            if part.hitBudget { break }
        }
        return Reading(lines: newestFirst.reversed(), oldest: oldest,
                       reachedCutoff: reached, bytesRead: bytes)
    }

    private struct Part {
        var lines: [String] = []      // newest first
        var oldest: String?
        var bytes = 0
        var reachedCutoff = false
        var hitBudget = false
    }

    private static func readBackwards(_ url: URL, cutoffText: String, budget: Int) -> Part {
        var part = Part()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return part }
        defer { try? handle.close() }
        guard var position = try? handle.seekToEnd() else { return part }

        var endChecked = false
        var carry = Data()                // the start of a line whose beginning is in the next chunk
        var pendingContinuation: [String] = []   // lines with no stamp, waiting for their stamped line
        func finish(_ line: String) -> Bool {      // true to stop reading
            guard !line.isEmpty else { return false }
            guard let stamp = stamp(of: line) else { pendingContinuation.append(line); return false }
            if stamp < cutoffText { part.reachedCutoff = true; return true }
            part.lines.append(contentsOf: pendingContinuation.reversed().map { $0 })
            pendingContinuation = []
            part.lines.append(line)
            part.oldest = stamp
            return false
        }

        while position > 0, part.bytes < budget {
            let size = UInt64(min(chunk, Int(position), budget - part.bytes))
            position -= size
            try? handle.seek(toOffset: position)
            guard var data = try? handle.read(upToCount: Int(size)) else { break }
            part.bytes += data.count
            // The guard may be writing as this reads: a last line that has no newline yet
            // is half written, and a half line parsed as a whole one is wrong. Leave it out.
            if !endChecked {
                endChecked = true
                if data.last != UInt8(ascii: "\n") {
                    data = data.lastIndex(of: UInt8(ascii: "\n")).map { Data(data[...$0]) } ?? Data()
                }
            }
            data.append(carry)
            // split into lines; the first piece may be a partial line
            let pieces = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            guard let head = pieces.first else { continue }
            carry = Data(head)
            for piece in pieces.dropFirst().reversed() {
                if finish(String(decoding: piece, as: UTF8.self)) { return part }
            }
        }
        if position == 0, !carry.isEmpty {
            _ = finish(String(decoding: carry, as: UTF8.self))
        } else if position > 0 {
            part.hitBudget = true
        }
        return part
    }

    /// The leading "yyyy-MM-dd HH:mm:ss" of a line, or nil when it has none.
    static func stamp(of line: String) -> String? {
        guard line.utf8.count >= 19 else { return nil }
        let prefix = line.prefix(19)
        // 4 digits, dash, 2, dash, 2, space, 2, colon, 2, colon, 2
        let chars = Array(prefix.utf8)
        let digits = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        guard digits.allSatisfy({ chars[$0] >= 48 && chars[$0] <= 57 }),
              chars[4] == 45, chars[7] == 45, chars[10] == 32, chars[13] == 58, chars[16] == 58
        else { return nil }
        return String(prefix)
    }
}
