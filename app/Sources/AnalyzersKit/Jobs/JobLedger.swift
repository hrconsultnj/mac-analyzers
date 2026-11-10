import Foundation

/// One line of `app-jobs.jsonl`: a pointer to a finished job, never its output.
/// The engine logs hold what happened; this holds who started it and what the
/// logs can't: failures before logging, and cancels.
public struct JobLedgerEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public let kind: JobKind
    public let intent: JobIntent
    /// `user`, `schedule:<label>`, `setup` or `update`.
    public let trigger: String
    public let start: Date?
    public let end: Date
    public let exit: Int32?
    public let cancelled: Bool
    public let runHeader: String?

    public init(id: UUID, kind: JobKind, intent: JobIntent, trigger: String, start: Date?,
                end: Date, exit: Int32?, cancelled: Bool, runHeader: String?) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.trigger = trigger
        self.start = start
        self.end = end
        self.exit = exit
        self.cancelled = cancelled
        self.runHeader = runHeader
    }
}

/// The index of app-started jobs: one JSON line each, newest last, capped.
public actor JobLedger {

    public static let lineCap = 500

    /// `~/mac-analyzers/reports/app-jobs.jsonl`. Built from the home folder
    /// directly: `AnalyzersPaths.suiteRoot` can be inside the app bundle, and
    /// the app never writes there.
    public static let standard = JobLedger(
        url: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "mac-analyzers/reports/app-jobs.jsonl"))

    public let url: URL
    private let cap: Int

    public init(url: URL, cap: Int = JobLedger.lineCap) {
        self.url = url
        self.cap = cap
    }

    public func append(_ entry: JobLedgerEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // At most `cap` short lines (~100 KB): read, append, trim, replace atomically.
        var existing = (try? Data(contentsOf: url)) ?? Data()
        if let last = existing.last, last != 10 { existing.append(10) }   // repair a torn last line
        existing.append(data)
        existing.append(10)
        var all = Self.lines(in: existing)
        if all.count > cap { all = Array(all.suffix(cap)) }
        let out = Data(all.flatMap { $0 + [10] })
        try? out.write(to: url, options: .atomic)
    }

    /// Newest first.
    public func entries(limit: Int = 500) -> [JobLedgerEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Self.lines(in: data).suffix(limit).reversed().compactMap {
            try? decoder.decode(JobLedgerEntry.self, from: Data($0))
        }
    }

    private static func lines(in data: Data) -> [[UInt8]] {
        data.split(separator: 10, omittingEmptySubsequences: true).map { Array($0) }
    }
}
