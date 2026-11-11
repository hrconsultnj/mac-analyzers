import AnalyzersKit
import Foundation

/// A run inside one engine log, found again later. A route holds an
/// identifier rather than the run, so this names the log, the run's banner and
/// which of the identical banners it is: the nth block with that exact banner,
/// counting from the oldest. A position in the file would not do — it shifts
/// whenever the log grows past the parser's window — and a banner alone is not
/// unique, because two runs in the same minute can share one.
struct RunReference: Hashable, Codable {
    let log: EngineLog
    let header: String
    let ordinal: Int

    init(log: EngineLog, header: String, ordinal: Int) {
        self.log = log
        self.header = header
        self.ordinal = ordinal
    }

    /// The reference to a block of a newest-first run list.
    init(log: EngineLog, run: LogRun, in runs: [LogRun]) {
        let position = runs.firstIndex(of: run) ?? 0
        self.init(log: log, header: run.header,
                  ordinal: runs[(position + 1)...].filter { $0.header == run.header }.count)
    }

    private enum CodingKeys: String, CodingKey { case log, header, ordinal }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .log)
        guard let log = EngineLog(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .log, in: container,
                                                   debugDescription: "unknown log \(raw)")
        }
        self.log = log
        header = try container.decode(String.self, forKey: .header)
        // a location saved before ordinals existed names the first run with that banner
        ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(log.rawValue, forKey: .log)
        try container.encode(header, forKey: .header)
        try container.encode(ordinal, forKey: .ordinal)
    }

    /// The run this refers to in a newest-first list, or nil when the log has
    /// moved on and it is gone.
    func resolve(in runs: [LogRun]) -> LogRun? {
        runs.enumerated().first { position, run in
            run.header == header && runs[(position + 1)...].filter { $0.header == header }.count == ordinal
        }?.element
    }
}
