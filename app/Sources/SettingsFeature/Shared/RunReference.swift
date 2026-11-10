import AnalyzersKit
import Foundation

/// A run inside one engine log, found again later. A route holds an
/// identifier rather than the run, so this names the log, the run's header
/// line and the run's index in the log (the parser's own `LogRun.id`, which
/// does not shift when newer runs are appended). The header alone is not
/// unique — two runs in the same minute can share one — so the index picks
/// between them, and the header confirms it is still the same run.
struct RunReference: Hashable, Codable {
    let log: EngineLog
    let header: String
    let index: Int

    init(log: EngineLog, header: String, index: Int) {
        self.log = log
        self.header = header
        self.index = index
    }

    private enum CodingKeys: String, CodingKey { case log, header, index }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .log)
        guard let log = EngineLog(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .log, in: container,
                                                   debugDescription: "unknown log \(raw)")
        }
        self.log = log
        header = try container.decode(String.self, forKey: .header)
        index = try container.decode(Int.self, forKey: .index)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(log.rawValue, forKey: .log)
        try container.encode(header, forKey: .header)
        try container.encode(index, forKey: .index)
    }

    /// The run this refers to: the one with the saved index when its header
    /// still matches, otherwise the first run with that header (the log has
    /// moved on), otherwise nil.
    func resolve(in runs: [LogRun]) -> LogRun? {
        runs.first { $0.id == index && $0.header == header }
            ?? runs.first { $0.header == header }
    }
}
