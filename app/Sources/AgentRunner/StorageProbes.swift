import Foundation
import AnalyzersKit

// `agent-runner --probe-storage <caches|downloads|temp|spotlight|disk> [--log <file>]` prints what a
// Storage screen lists, as the screen will: tab → group → rows, each with its count and total, from
// the newest preview in the real engine logs (or `--log <file>`, a stand-in log for a case the real
// data lacks). It reads; it runs nothing and changes nothing. The probe FAILS when a title is a
// path, a hash, a banner or an engine token, when a title repeats inside a group, when a title holds
// " — ", or when one tab holds every row of a screen that has tabs.

private func human(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    return String(format: "%.0f KB", Double(bytes) / 1024)
}

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

private func looksRaw(_ title: String) -> String? {
    if title.hasPrefix("/") || title.hasPrefix("~") || title.contains("/Users/") || title.contains("/private/") {
        return "is a path"
    }
    if title.range(of: #"[0-9a-fA-F]{12,}"#, options: .regularExpression) != nil { return "contains a hash" }
    if title.contains(" | ") { return "looks like a banner" }
    if title.contains(" — ") { return "holds \" — \" (a title built from two parts)" }
    for token in ["DRY", "[", ".sh", "--"] where title.contains(token) { return "contains engine text \"\(token)\"" }
    return nil
}

/// Prints tab → group → rows and returns the problems found.
/// `namesAreFiles`: the titles are the files' own names (Downloads), which are what they are, so only repeats are checked.
private func printLevels<C: StorageCategory>(_ rows: StorageRows, _ type: C.Type, perGroup: Int = 6,
                                              namesAreFiles: Bool = false) -> [String] {
    var problems: [String] = []
    let filled = rows.filled(type)
    print("tabs: " + filled.map { "\($0.title) (\(rows.count(in: $0)) · \(human(rows.bytes(in: $0))))" }.joined(separator: "  |  "))
    if filled.count == 1, rows.rows.count > 0, C.allCases.count > 1 {
        problems.append("one tab holds every row: \(filled[0].title)")
    }
    for category in filled {
        print("\n[\(category.title)]  \(rows.count(in: category)) rows · \(human(rows.bytes(in: category)))")
        var order: [String] = []
        var groups: [String: [StorageRow]] = [:]
        for row in rows.rows(in: category) {
            let key = row.group ?? ""
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        for key in order {
            let members = groups[key] ?? []
            let total = members.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            let kept = members.filter { !$0.isChoosable }.count
            print("  \(key.isEmpty ? "(no group)" : key)  — \(members.count) item\(members.count == 1 ? "" : "s") · \(human(total))\(kept > 0 ? " · \(kept) kept" : "")")
            var seen: Set<String> = []
            for row in members {
                if !seen.insert(row.title).inserted { problems.append("\(category.title) / \(key): title \"\(row.title)\" repeats") }
                if !namesAreFiles, let why = looksRaw(row.title) { problems.append("\(category.title) / \(key): \"\(row.title)\" \(why)") }
            }
            for row in members.prefix(perGroup) {
                let size = row.bytes.map(human) ?? row.valueText ?? ""
                print("      \(pad(row.title, 46)) \(pad(size, 10)) \(row.keptReason.map { "KEPT: \($0)" } ?? (row.detail ?? ""))")
            }
            if members.count > perGroup { print("      … and \(members.count - perGroup) more") }
        }
    }
    return problems
}

private func relative(_ date: Date?) -> String { StorageLog.ago(date) ?? "unknown" }

func probeStorage(_ which: String, logOverride: String?) -> Never {
    var problems: [String] = []
    func block(_ kind: JobKind) -> WholeRun.Block? {
        if let logOverride {
            guard case .block(let found) = WholeRun.newestPreview(in: URL(fileURLWithPath: logOverride)) else { return nil }
            return found
        }
        return StorageLog.newestPreview(of: kind)
    }

    switch which {
    case "caches":
        guard let run = block(.storageClean) else { print("no preview in the log yet"); exit(0) }
        let review = CacheReview.build(lines: run.lines, banner: run.banner)
        print("mode: \(review.mode.title) — \(review.mode.sentence)")
        print("\(review.rows.rows.count) rows · \(human(review.rows.totalBytes)) · free \(review.freeSpace ?? "?")")
        if let note = review.snapshotNote { print("snapshots: \(note)") }
        if let note = review.keptNote { print("kept: \(note)") }
        problems += printLevels(review.rows, CacheCategory.self)

    case "downloads":
        guard let run = block(.janitor) else { print("no preview in the log yet"); exit(0) }
        let review = DownloadReview.build(lines: run.lines)
        print("\(review.rows.rows.count) rows · \(human(review.rows.totalBytes)) · \(review.keptByPattern) on your keep list")
        print("(run block: \(run.lines.count) lines, read whole)")
        problems += printLevels(review.rows, DownloadCategory.self, perGroup: 3, namesAreFiles: true)

    case "temp":
        guard let run = block(.tempClean) else { print("no audit in the log yet"); exit(0) }
        let review = TempReview.build(from: TempCleanParser.parse(runHeader: run.banner, lines: run.lines))
        print("free \(review.freeSpace ?? "?") · temp on disk \(review.tempOnDisk ?? "?") · agent folders \(review.agentFolders ?? "?")")
        print("\(review.ready.count) ready (\(human(review.readyBytes))) · \(review.diskImages.count) disk images")
        problems += printLevels(review.rows, TempCategory.self, perGroup: 8)
        for image in review.diskImages { print("disk image \(image.name): \(human(image.sizeBytes)) from \(image.imagePath)") }

    case "spotlight":
        guard let run = block(.spotlight) else { print("no audit in the log yet"); exit(0) }
        let review = SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: run.banner, lines: run.lines))
        print("\(review.status) \(review.verdictSentence)")
        print("\(review.fenced.count) fenced · \(review.unfenced.count) not fenced · unfenced bulk \(review.unfencedBulkBytes.map(human) ?? "?")\n")
        var seen: [String: Set<String>] = [:]
        for folder in review.folders {
            print("  \(pad(folder.project, 22)) \(pad(folder.title, 44)) \(pad(human(folder.sizeBytes), 9)) \(pad(folder.state.title, 11)) \(folder.shortPath)")
            if !seen[folder.project, default: []].insert(folder.title).inserted { problems.append("\(folder.project): title \"\(folder.title)\" repeats") }
            if let why = looksRaw(folder.title) { problems.append("\(folder.project): \"\(folder.title)\" \(why)") }
        }

    case "fixtures":
        print("-- Caches & Builds example"); problems += printLevels(StorageFixtures.caches(), CacheCategory.self)
        print("\n-- Downloads example"); problems += printLevels(StorageFixtures.downloads(), DownloadCategory.self, perGroup: 3, namesAreFiles: true)
        // files kept only in iCloud are shown with what they are and never offered for a tick
        let cloud = StorageFixtures.downloads().rows.filter { $0.group == Names.Download.onlyInICloud }
        if cloud.isEmpty { problems.append("the Downloads example has no iCloud-only rows") }
        for row in cloud where row.isChoosable || row.bytes != nil || row.valueText == nil {
            problems.append("iCloud-only row \"\(row.title)\" is offered for a tick, counted as freeing space, or has no size")
        }
        print("\n-- Temp & Agents example"); problems += printLevels(StorageFixtures.temp(), TempCategory.self)
        print("\n-- a finished Caches & Builds run (what it did to each row)"); problems += printLevels(StorageFixtures.cachesRun(), CacheCategory.self)
        // an apply's prunes, Docker and snapshot thinning each show what they did
        let ran = StorageFixtures.cachesRun().rows
        for (id, outcome) in [("prune:pnpm", Names.Prune.ran), ("prune:npm", Names.Prune.skipped),
                              ("prune:docker", Names.Prune.ran), ("prune:snapshots", Names.Prune.ran)] {
            let seen = ran.first { $0.id == id }?.valueText
            if seen != outcome { problems.append("a finished Caches run: \(id) shows \"\(seen ?? "nothing")\", expected \"\(outcome)\"") }
        }
        print("\n-- a finished Downloads run"); problems += printLevels(StorageFixtures.downloadsRun(), DownloadCategory.self, perGroup: 3, namesAreFiles: true)

    case "disk":
        for task in StorageTasks.load() {
            let size = task.reclaimableBytes.map(human) ?? "—"
            print("\(pad(task.title, 18)) \(pad(size, 9)) \(pad(relative(task.measuredAt), 20)) \(task.detail)")
        }
        let series = DiskRunway.series()
        let windowed = LogParser.runs(for: .storageClean).filter { run in
            run.lines.contains { $0.contains("Free space now:") } && RunDate.date(of: run.header) != nil
        }.count
        print("\nrunway from \(series.count) runs of the whole storage log (the newest-20-runs window would have held \(windowed))")
        if let last = series.last, let first = series.first {
            print("  first \(String(format: "%.1f", first.freeGiB)) GiB, newest \(String(format: "%.1f", last.freeGiB)) GiB, spanning \(Int(last.day - first.day)) days")
        }
        print("  \(DiskRunway.forecast(series).map { "full in \($0.text)" } ?? "no forecast (the trend is flat or up, or there is not a week of figures)")")

    default:
        FileHandle.standardError.write(Data("usage: agent-runner --probe-storage <caches|downloads|temp|spotlight|disk> [--log <file>]\n".utf8))
        exit(2)
    }

    if problems.isEmpty { print("\nno raw titles, no repeats, no \" — \"") ; exit(0) }
    print("\nPROBLEMS (\(problems.count)):")
    problems.prefix(30).forEach { print("  \($0)") }
    exit(1)
}
