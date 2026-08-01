import AnalyzersKit
import Foundation
import SwiftUI

/// Every pane's load goes through the shared query cache: serialized (one
/// expensive producer at a time), deduped by call site, and served from a
/// short TTL so re-entering a pane or a refresh tick costs nothing. The
/// key comes free from the call site — nothing to pass, nothing to collide.
func detachedLoad<T: Sendable>(_ work: @escaping @Sendable () -> T,
                               ttl: TimeInterval = 3,
                               key: String = "\(#fileID):\(#line)",
                               assign: @escaping @MainActor (T) -> Void) {
    Task {
        let value = await LoadCoordinator.shared.value(key: key, ttl: ttl, produce: work)
        guard !Task.isCancelled else { return }
        await MainActor.run { assign(value) }
    }
}

/// One run (or day, for event-style logs) inside a log file.
struct LogRun: Identifiable, Hashable {
    let id: Int
    let header: String
    let lines: [String]

    /// First content line that reads as a summary (DONE/DRY/freed …).
    var summary: String? {
        lines.first {
            !$0.hasPrefix("### ") &&
            ($0.contains("DONE") || $0.contains("DRY RUN") || $0.contains("freed")
             || $0.contains("reclaim") || $0.contains("guard started") || $0.first?.isNumber == true)
        }
    }

    var itemCount: Int {
        lines.filter { !$0.hasPrefix("### ") }.count
    }
}

/// Push target: a run inside a specific log (the kind carries icon/colors).
struct RunRoute: Hashable {
    let kind: LogKind
    let run: LogRun
}

/// ONE typed route for everything pushable in the logs world — a typed path
/// array ([LogRoute]) instead of an opaque NavigationPath is what lets the
/// shell snapshot and restore navigation for browser-style back/forward.
enum LogRoute: Hashable {
    case log(LogKind)
    case run(RunRoute)
    case forensics(ForensicsRoute)
}

enum LogParser {

    /// Parse a log file into runs, newest first.
    static func runs(for kind: LogKind) -> [LogRun] {
        guard let url = kind.url,
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 262_144
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return text.contains("====") ? runBlocks(lines) : dayGroups(lines)
    }

    /// Report-style logs: runs delimited by ===== separators; a short block
    /// containing "|" is the header for the body block that follows.
    private static func runBlocks(_ lines: [String]) -> [LogRun] {
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.allSatisfy({ $0 == "=" }) {
                if !current.isEmpty { blocks.append(current); current = [] }
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { blocks.append(current) }

        var result: [LogRun] = []
        var pendingHeader: String?
        for block in blocks {
            if block.count <= 2, let first = block.first, first.contains("|") {
                pendingHeader = block.joined(separator: " · ")
                continue
            }
            let header = pendingHeader ?? block.first ?? "Run"
            let body = pendingHeader == nil ? Array(block.dropFirst()) : block
            result.append(LogRun(id: result.count, header: header, lines: body))
            pendingHeader = nil
        }
        return result.reversed().prefix(20).map { $0 }
    }

    /// Event-style logs (guard): group by day, newest day first, newest line
    /// first inside the day.
    private static func dayGroups(_ lines: [String]) -> [LogRun] {
        var byDay: [(day: String, lines: [String])] = []
        for line in lines.suffix(400) {
            let day = String(line.prefix(10))
            if byDay.last?.day == day {
                byDay[byDay.count - 1].lines.append(line)
            } else {
                byDay.append((day, [line]))
            }
        }
        return byDay.reversed().enumerated().map { index, group in
            LogRun(id: index, header: group.day, lines: group.lines.reversed())
        }
    }

    // MARK: - line classification (shared by list + detail rows)

    static func badge(for line: String) -> (text: String, color: Color)? {
        if line.contains(" KILLED ") { return ("KILLED", .red) }
        if line.contains("CRITICAL") { return ("CRITICAL", .red) }
        if line.contains(" SPIKE ") { return ("SPIKE", .orange) }
        if line.contains("WARNING") { return ("WARN", .orange) }
        if line.contains("CAP-EXCEEDED") { return ("OVER CAP", .orange) }
        if line.contains("[KILLED]") || line.contains("[QUIT]") { return ("CLOSED", .red) }
        if line.contains("[DELETED]") { return ("DELETED", .red) }
        if line.contains("[EXEMPT]") { return ("EXEMPT", .blue) }
        if line.contains("[GONE]") { return ("GONE", .gray) }
        if line.contains("[DRY]") { return ("DRY", .blue) }
        if line.contains("DONE") { return ("DONE", .green) }
        if line.contains("FORENSICS") { return ("REPORT", .purple) }
        return nil
    }

    static func cleaned(_ line: String) -> String {
        var out = line
        for tag in ["[DRY]", "[KILLED]", "[QUIT]", "[DELETED]", "[EXEMPT]", "[GONE]"] {
            out = out.replacingOccurrences(of: tag, with: "")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
