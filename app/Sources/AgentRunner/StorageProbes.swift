import Foundation
import AnalyzersKit

// `agent-runner --probe-storage <caches|downloads|temp|spotlight|disk> [--log <file>]` prints
// what a Storage screen would list, built from the newest preview in the real
// engine logs, or from `--log <file>` (a stand-in log for a case the real data lacks); it reads them; it runs nothing and changes nothing). Every row
// is checked for the things the screens must never show — a path, a hash, a
// banner or an engine token as a title — and the probe fails if one gets through.

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

/// A title that is really a dump: a path, a hash, a banner, an engine token.
private func looksRaw(_ title: String) -> String? {
    if title.hasPrefix("/") || title.hasPrefix("~") || title.contains("/Users/") || title.contains("/private/") {
        return "is a path"
    }
    if title.range(of: #"[0-9a-fA-F]{12,}"#, options: .regularExpression) != nil { return "contains a hash" }
    if title.contains(" | ") { return "looks like a banner" }
    for token in ["DRY", "[", ".sh", "--"] where title.contains(token) { return "contains engine text \"\(token)\"" }
    return nil
}

private func relative(_ date: Date?) -> String {
    guard let date else { return "unknown" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

func probeStorage(_ which: String, logOverride: String?) -> Never {
    var problems: [String] = []
    func log(_ standard: URL) -> URL { logOverride.map { URL(fileURLWithPath: $0) } ?? standard }
    func check(_ title: String, context: String) {
        if let why = looksRaw(title) { problems.append("\(context): \"\(title)\" \(why)") }
    }

    switch which {
    case "caches":
        guard let run = StorageRunReader.run(in: log(AnalyzersPaths.storageAutoCleanLog), header: nil) else {
            print("no preview in the log yet"); exit(0)
        }
        let review = CacheReview.build(from: StorageCleanParser.parse(runHeader: run.header, lines: run.lines),
                                       roots: CacheReview.roots(in: run.lines))
        print("mode: \(review.mode.title) — \(review.mode.sentence)")
        print("\(review.candidates.count) folders in \(review.projects.count) projects · \(human(review.totalBytes)) · free \(review.freeSpace ?? "?")")
        for project in review.projects {
            print("\n\(project.name)  (\(human(project.sizeBytes)))")
            check(project.name, context: "project")
            for item in project.items {
                let used = item.lastUsed.map { relative($0) } ?? "gone"
                print("  \(pad(item.kind.title, 22)) \(pad(human(item.sizeBytes), 9)) \(pad(used, 18)) \(item.shortPath)")
                check(item.kind.title, context: "kind")
            }
        }
        for line in review.alsoWhenAllSelected { print("\nalso, only when everything is ticked: \(line)") }
        if let note = review.snapshotNote { print("snapshots: \(note)") }
        if let note = review.keptNote { print("kept: \(note)") }

    case "downloads":
        guard let run = StorageRunReader.run(in: log(AnalyzersPaths.janitorLog), header: nil) else {
            print("no preview in the log yet"); exit(0)
        }
        let review = DownloadReview.build(lines: run.lines)
        let all = review.candidates
        print("\(all.count) items · \(human(review.totalBytes)) · \(review.keptByPattern) kept by your patterns")
        print("(run block: \(run.lines.count) lines — the whole run, not the 256 KB tail)")
        print("\nby kind:")
        for kind in DownloadKind.allCases {
            let group = all.filter { $0.kind == kind }
            if !group.isEmpty { print("  \(pad(kind.title, 26)) \(pad(String(group.count), 6)) \(human(group.reduce(0) { $0 + $1.sizeBytes }))") }
        }
        print("by age:")
        for age in DownloadAge.allCases {
            let group = all.filter { $0.age() == age }
            if !group.isEmpty { print("  \(pad(age.title, 26)) \(pad(String(group.count), 6)) \(human(group.reduce(0) { $0 + $1.sizeBytes }))") }
        }
        print("by folder:")
        for source in [DownloadSource.downloads, .screenshots] {
            let group = all.filter { $0.source == source }
            print("  \(pad(source.title, 26)) \(pad(String(group.count), 6)) \(human(group.reduce(0) { $0 + $1.sizeBytes }))")
        }
        print("\nlargest 12:")
        for item in all.sorted(by: { $0.sizeBytes > $1.sizeBytes }).prefix(12) {
            print("  \(pad(item.name, 44)) \(pad(item.kind.title, 14)) \(pad(human(item.sizeBytes), 9)) \(item.why())")
        }

    case "temp":
        guard let run = StorageRunReader.run(in: log(AnalyzersPaths.tempCleanLog), header: nil) else {
            print("no audit in the log yet"); exit(0)
        }
        let review = TempReview.build(from: TempCleanParser.parse(runHeader: run.header, lines: run.lines))
        print("free \(review.freeSpace ?? "?") · temp on disk \(review.tempOnDisk ?? "?") · agent folders \(review.agentFolders ?? "?")")
        print("\(review.ready.count) ready (\(human(review.readyBytes))) · \(review.leftAloneCount) left alone · \(review.diskImages.count) disk images\n")
        var groups: [String] = []
        for row in review.rows where !groups.contains(row.group) { groups.append(row.group) }
        for group in groups {
            print(group)
            for row in review.rows where row.group == group {
                print("  \(pad(row.title, 44)) \(pad(row.state.title, 11)) \(pad(human(row.sizeBytes), 9)) \(row.outcome)")
                check(row.title, context: group)
            }
        }
        for image in review.diskImages { print("disk image \(image.name): \(human(image.sizeBytes)) from \(image.imagePath)") }

    case "spotlight":
        guard let run = StorageRunReader.run(in: log(AnalyzersPaths.spotlightAuditLog), header: nil) else {
            print("no audit in the log yet"); exit(0)
        }
        let review = SpotlightReview.build(from: SpotlightAuditParser.parse(runHeader: run.header, lines: run.lines))
        print("\(review.status) \(review.verdictSentence)")
        print("\(review.fenced.count) fenced · \(review.unfenced.count) not fenced · unfenced bulk \(review.unfencedBulkBytes.map(human) ?? "?")\n")
        for folder in review.folders {
            print("  \(pad(folder.project, 24)) \(pad(folder.kind.title, 18)) \(pad(human(folder.sizeBytes), 9)) \(pad(folder.state.title, 11)) \(folder.shortPath)")
            check(folder.project, context: "project")
        }

    case "disk":
        for task in StorageTasks.load() {
            let size = task.reclaimableBytes.map(human) ?? "—"
            print("\(pad(task.title, 18)) \(pad(size, 9)) \(pad(relative(task.measuredAt), 20)) \(task.detail)")
            check(task.title, context: "task")
        }

    default:
        FileHandle.standardError.write(Data("usage: agent-runner --probe-storage <caches|downloads|temp|spotlight|disk>\n".utf8))
        exit(2)
    }

    if problems.isEmpty { print("\nno raw titles") ; exit(0) }
    print("\nRAW TITLES (\(problems.count)):")
    problems.prefix(30).forEach { print("  \($0)") }
    exit(1)
}
