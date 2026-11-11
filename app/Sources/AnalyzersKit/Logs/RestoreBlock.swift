import Foundation

/// A restore's own block in a cleaner's log.
///
/// Undo puts items back from the Trash and writes a receipt for each in the log of the
/// cleaner that moved them there. Written bare, those lines land under whichever run is
/// newest in that log, which is usually not the run the items came from and can be a
/// preview that is waiting for review. So one Restore action writes one block of its own,
/// in the shape the logs' other blocks have: a rule, a banner (date and time to the second,
/// a name that reads as a restore, `APPLY`), a rule, then the lines.
///
///     ====================
///     2026-11-11 05:12:03 | restore from Undo | APPLY
///     ====================
///     Put back 3 item(s)
///     [RESTORED] 1.5 MB  /Users/x/Downloads/a.zip
///     [RESTORED·member]  /tmp/x/a1
///     [RESTORED] 2 MB  /tmp/x/a*
///
/// `LogParser` leaves these blocks out of the runs it returns unless asked for them
/// (Activity asks), so no other reader — a screen's "latest run", a total, the matcher of a
/// job's own block — can mistake one for a run of the cleaner. A restore receipt's
/// pairing with its `[TRASHED]` line is the ledger's, by path, and does not depend on
/// where the line sits. Old logs hold bannerless `[RESTORED]` lines; they still read as before.
public enum RestoreBlock {

    /// What the banner says between its bars; `isRestore` looks for exactly this.
    public static let name = "restore from Undo"

    public static func banner(at date: Date) -> String {
        "\(stamp.string(from: date)) | \(name) | APPLY"
    }

    /// The text to append to a log for one restore action: the banner and the lines.
    /// `lines` are the receipt lines as the ledger writes them.
    public static func text(lines: [String], at date: Date = Date()) -> String {
        let rule = String(repeating: "=", count: 64)
        let count = lines.filter { $0.hasPrefix(pairingTag) }.count
        var out = ["", rule, banner(at: date), rule]
        out.append(count == 0 ? "Nothing was put back" : "Put back \(count) item(s)")
        out.append(contentsOf: lines)
        return out.joined(separator: "\n") + "\n"
    }

    /// Whether a run's header (or a banner line) is a restore's.
    public static func isRestore(header: String) -> Bool {
        header.contains("| \(name) |")
    }

    static let pairingTag = "[RESTORED]"

    /// One thing a restore put back.
    public struct Item: Sendable, Equatable {
        public let size: String
        public let path: String
    }

    /// The items a restore block put back (its `[RESTORED]` lines; member lines
    /// belong to a family's own line and are not counted twice).
    public static func items(in lines: [String]) -> [Item] {
        lines.compactMap { line in
            guard line.hasPrefix(pairingTag) else { return nil }
            let rest = line.dropFirst(pairingTag.count).trimmingCharacters(in: .whitespaces)
            guard let split = rest.range(of: "  ") else { return nil }
            let path = rest[split.upperBound...].trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/") else { return nil }
            return Item(size: String(rest[..<split.lowerBound]), path: path)
        }
    }

    /// "Restored 3 Items".
    public static func resultText(count: Int) -> String {
        if count == 0 { return Names.Restore.nothing }
        return "\(Names.Restore.restored) \(count) \(count == 1 ? Names.Restore.item : Names.Restore.items)"
    }

    /// What Activity shows for the run: it freed and found nothing.
    public static func summary(_ run: LogRun) -> ActivitySummary {
        ActivitySummary(resultText(count: items(in: run.lines).count))
    }

    /// The run's screen: the items it put back, biggest first.
    public static func outcome(_ run: LogRun) -> ActivityOutcome {
        let put = items(in: run.lines)
        guard !put.isEmpty else { return ActivityOutcome(sections: []) }
        let rows = put.enumerated().map { index, item in
            ActivityOutcome.Item(id: index, title: (item.path as NSString).lastPathComponent,
                                 detail: (item.path as NSString).deletingLastPathComponent
                                     .replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                                 trailing: item.size)
        }
        return ActivityOutcome(sections: [ActivityOutcome.Section(
            id: 0, title: Names.Restore.putBack, tone: .done, items: rows, hidden: 0)])
    }

    // MARK: - reading a log that holds restore blocks

    private static func isRule(_ line: String) -> Bool { line.count >= 3 && line.allSatisfy { $0 == "=" } }

    /// Takes every restore block out of a log's lines (trimmed, blanks dropped, rules kept):
    /// what is left is the log as it would read had no restore ever happened, and the blocks
    /// come back as runs of their own, in file order. A block is its banner, the rule after it,
    /// and the lines up to the next rule or banner; the rule before it goes with it.
    public static func split(_ lines: [String]) -> (rest: [String], restores: [LogRun]) {
        guard lines.contains(where: { isRestore(header: $0) }) else { return (lines, []) }
        var rest: [String] = []
        var found: [LogRun] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard isRestore(header: line), RunMatcher.banner(in: line) != nil else {
                rest.append(line)
                index += 1
                continue
            }
            if let last = rest.last, isRule(last) { rest.removeLast() }
            index += 1
            if index < lines.count, isRule(lines[index]) { index += 1 }
            var body: [String] = []
            while index < lines.count, !isRule(lines[index]), RunMatcher.banner(in: lines[index]) == nil {
                body.append(lines[index])
                index += 1
            }
            found.append(LogRun(id: found.count, header: line, lines: body))
        }
        return (rest, found)
    }

    /// Puts restore runs among a log's runs (newest first) where their dates belong; the
    /// log's own runs keep their order.
    public static func merge(restores: [LogRun], into runs: [LogRun]) -> [LogRun] {
        guard !restores.isEmpty else { return runs }
        var pending = restores.reversed().map { $0 }      // newest first
        var merged: [LogRun] = []
        for run in runs {
            let when = RunDate.date(of: run.header)
            while let next = pending.first, let nextDate = RunDate.date(of: next.header),
                  when.map({ nextDate >= $0 }) ?? false {
                merged.append(next)
                pending.removeFirst()
            }
            merged.append(run)
        }
        return merged + pending
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
