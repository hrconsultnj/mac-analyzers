import Foundation

/// Every run in a block log, for totals over a period.
///
/// `LogParser.runs(for:)` reads the last 256 KB and keeps the newest 20 runs:
/// the right size for a list, the wrong one for a 30-day sum, because a log that
/// is previewed every few minutes pushes the runs that freed space out of both
/// limits within a day. The grouping is `LogParser.runBlocks`, the one the list
/// uses, so a run begins in the same place for every reader.
extension LogParser {

    /// Newest first, no window, no cap. Day-style logs (the guard) have no
    /// block structure and read as `runs(for:)` does.
    public static func allRuns(for kind: EngineLog, includingRestores: Bool = false) -> [LogRun] {
        kind.url.map { allRuns(at: $0, includingRestores: includingRestores) } ?? []
    }

    /// The same over any file (a probe reads a copy the way the real one is read).
    public static func allRuns(at url: URL, includingRestores: Bool = false) -> [LogRun] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        guard data.range(of: Data("====".utf8)) != nil else { return runs(at: url, includingRestores: includingRestores) }
        return runBlocks(LogLines.lines(in: data), includingRestores: includingRestores, limit: nil)
    }
}
