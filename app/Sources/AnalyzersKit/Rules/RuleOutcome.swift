import Foundation

/// One line of `rule-outcomes.jsonl`: what a rule would have done, or would have done but was kept from doing. Written by
/// the rules engine in Watching, read by the Memory Guard screen ("Would have stopped 3 times this week") and the menu-bar
/// panel. Nothing was done when one of these was written.
public struct RuleOutcome: Codable, Sendable, Identifiable, Hashable {
    public let ref: String
    public let time: Date
    public let rule: String
    /// `watching` for every row this version writes.
    public let mode: String
    /// `would` (it would have acted) or `kept` (it would have, and a protection said no).
    public let result: String
    public let category: String
    public let kind: String
    public let name: String
    public let pid: Int?
    /// The kernel's start time of the process, seconds, so a pid that was recycled is a different row.
    public let startSeconds: Int?
    public let members: Int
    public let bytes: Int64
    public let action: String
    public let why: String
    public let keptBecause: String?

    public var id: String { ref }
    public var isWould: Bool { result == "would" }
}

/// One line of the menu-bar panel's Memory tab: what the rules would have done today in one category, and where it opens.
public struct RuleLine: Identifiable, Sendable, Hashable {
    public let category: CensusGroup.Category
    public let text: String
    /// The deep link of the Memory Guard tab for the category.
    public let target: String
    public var id: String { category.rawValue }
}

/// `reports/memory/rule-outcomes.jsonl`: append-only, one JSON object per line, read back only as far as a period needs.
public enum RuleOutcomes {

    public static var file: URL { AnalyzersPaths.memoryReports.appending(path: "rule-outcomes.jsonl") }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Adds the rows to the end of the file (made if it is not there). Never rewrites what is already in it.
    public static func append(_ outcomes: [RuleOutcome], to url: URL = file) {
        guard !outcomes.isEmpty else { return }
        let lines = outcomes.compactMap { try? encoder.encode($0) }.compactMap { String(data: $0, encoding: .utf8) }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Every row from `start` on, newest first. The file is read from its end, at most `maxBytes`.
    public static func read(since start: Date, from url: URL = file, maxBytes: Int = 8 * 1_048_576) -> [RuleOutcome] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let from = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: from)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        var lines = text.split(whereSeparator: \.isNewline)
        if from > 0, !lines.isEmpty { lines.removeFirst() }       // the first line of a cut read is a piece
        return lines.compactMap { try? decoder.decode(RuleOutcome.self, from: Data($0.utf8)) }
            .filter { $0.time >= start }
            .sorted { $0.time > $1.time }
    }

    /// The panel's lines for today's rows: one per category that has something, in the order Apps, Tools, macOS. Words say what
    /// WOULD have happened: nothing in this version is done.
    public static func todayLines(_ rows: [RuleOutcome]) -> [RuleLine] {
        let would = rows.filter(\.isWould)
        var lines: [RuleLine] = []
        for (category, tab) in [(CensusGroup.Category.apps, "apps"), (.tools, "tools"), (.system, "macos")] {
            let mine = would.filter { $0.category == category.rawValue }
            guard !mine.isEmpty else { continue }
            let stops = mine.filter { $0.action == "stop" }
            let asks = mine.filter { $0.action == "propose" || $0.action == "askToQuit" }
            let told = mine.filter { $0.action == "notify" }
            var parts: [String] = []
            if !stops.isEmpty { parts.append("would have stopped \(stops.count) (\(MemorySize.text(stops.reduce(Int64(0)) { $0 + $1.bytes }, .headline)))") }
            if !asks.isEmpty { parts.append("\(asks.count) would have waited for you") }
            if !told.isEmpty { parts.append("\(told.count) to know about") }
            lines.append(RuleLine(category: category, text: "\(category.shortTitle): \(parts.joined(separator: ", "))", target: "guard:\(tab)"))
        }
        return lines
    }

    /// How many times a rule would have acted in `rows`, and how many times a protection kept it.
    public static func counts(_ rows: [RuleOutcome], rule: String) -> (would: Int, kept: Int) {
        let mine = rows.filter { $0.rule == rule }
        return (mine.filter(\.isWould).count, mine.filter { !$0.isWould }.count)
    }
}
