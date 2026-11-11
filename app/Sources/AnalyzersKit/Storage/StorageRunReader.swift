import Foundation

/// The whole of one cleanup run, read back from its engine log.
///
/// `LogParser` reads the last 256 KB of a log, which is right for a list of
/// recent runs and wrong for a run that is bigger than that: the Downloads
/// cleanup lists one line per file, so a Mac with 6,000 old screenshots writes
/// 600 KB for one preview. A review built from a cut-off run would show part
/// of what an apply could touch. This reads back from the end of the log until
/// it reaches the run's own banner, so a review always shows the whole run.
public enum StorageRunReader {

    /// A run, as the log recorded it.
    public struct Run: Sendable {
        /// The banner line, trimmed — what `Job.runHeader` holds for a tracked run.
        public let header: String
        /// Every line after the banner up to the next run, trimmed, blank lines dropped.
        public let lines: [String]
        /// True when the run is a dry run (a preview).
        public var isPreview: Bool { header.contains("DRY RUN") }
    }

    /// How far back from the end of a log to look. Larger than any run seen.
    public static let reach = 32 * 1_048_576

    /// The run whose banner is `header`; with no header, the newest preview.
    public static func run(in log: URL, header: String?) -> Run? {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(reach) ? size - UInt64(reach) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // the first line may be cut in half
        return run(in: lines, header: header)
    }

    /// The same selection over lines already in memory.
    static func run(in lines: [String], header: String?) -> Run? {
        let banners = lines.indices.filter { RunMatcher.banner(in: lines[$0]) != nil }
        let pick: Int?
        if let header {
            let wanted = normalized(header)
            pick = banners.last { normalized(lines[$0]) == wanted }
        } else {
            pick = banners.last { lines[$0].contains("DRY RUN") }
        }
        guard let first = pick else { return nil }
        let end = banners.first { $0 > first } ?? lines.endIndex
        return Run(header: lines[first], lines: Array(lines[(first + 1)..<end]))
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
