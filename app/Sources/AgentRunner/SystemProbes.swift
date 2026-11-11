import Foundation
import AnalyzersKit

// Headless proofs for the System screens: each prints the rows its screen
// would show, from real data (or from a file named on the command line), so
// the row model is checked before any view exists.

private func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width - 1)) + " " : text + String(repeating: " ", count: width - text.count)
}

private func option(_ name: String, in args: [String]) -> String? {
    guard let at = args.firstIndex(of: name), args.indices.contains(at + 1) else { return nil }
    return args[at + 1]
}

func probeStartup(_ args: [String]) -> Never {
    let url = option("--file", in: args).map { URL(fileURLWithPath: $0) } ?? StartupInventory.file
    guard let inventory = StartupInventory.latest(at: url) else {
        print("no inventory at \(url.path) (run the audit once)")
        exit(1)
    }
    let ran = inventory.ranAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unknown"
    let leftovers = inventory.leftovers.count
    print("\(inventory.items.count) items, \(leftovers) leftover\(leftovers == 1 ? "" : "s") · audit ran \(ran) · \(inventory.wasDryRun ? "looked only" : "removed leftovers")")
    func line(_ title: String, _ item: StartupItem, indent: String) -> String {
        let finding = item.findingTitle.isEmpty ? "-" : item.findingTitle
        let admin = item.needsAdministrator ? "admin" : ""
        let owner = "owner: \(item.owner) (\(item.ownerSource.rawValue))"
            + (item.ownerNote.map { " [signature failed: \($0)]" } ?? "")
        let removable = item.canRemove ? "  [can remove]" : ""
        let columns: [String] = [pad(title, 30), pad(item.kind.title, 15), pad(item.stateTitle, 12),
                                 pad(finding, 18), pad(admin, 7), owner + removable]
        return indent + columns.joined()
    }
    for category in StartupItem.Category.allCases {
        let groups = inventory.groups(in: category)
        print("\n\(category.title) — \(inventory.items(in: category).count) items in \(groups.count) groups")
        for group in groups {
            if group.count == 1, let item = group.items.first {
                print(line(group.standaloneTitle(for: item), item, indent: "  "))
            } else {
                print("  ▸ " + pad(group.name, 30) + pad(group.countText, 15) + group.stateSummary)
                for item in group.items { print(line(item.name, item, indent: "      ")) }
            }
        }
    }
    let banner = " login-items-audit  |  DRY RUN  |  \(inventory.stamp)"
    print("\nrun stamp \(inventory.stamp): from the run that printed its banner: \(inventory.isFromRun(printing: [banner]) ? "yes" : "NO")"
          + " · from a run stamped a minute later: \(inventory.isFromRun(printing: [" login-items-audit  |  DRY RUN  |  2099-01-01 00:00:00"]) ? "YES" : "no")")
    print("a Remove can be narrowed to the selected rows: \(StartupRemoval.canNarrowToSelection ? "yes" : "no — it would remove every user-level leftover")")
    print("removable from the app: \(inventory.removable.count)")
    for item in inventory.leftovers {
        print("  \(item.name) — \(item.explanation)")
        if let fix = item.fixCommand { print("      \(fix)") }
    }
    let problems = inventory.levelProblems()
    print(problems.isEmpty ? "\nlevels: ok" : "\nlevels: PROBLEMS\n" + problems.map { "  " + $0 }.joined(separator: "\n"))
    exit(problems.isEmpty ? 0 : 1)
}

func probeStartupChanges(_ args: [String]) -> Never {
    let url = option("--log", in: args).map { URL(fileURLWithPath: $0) } ?? AnalyzersPaths.persistenceLog
    let changes = StartupChangeParser.read(at: url)
    let inventory = StartupInventory.latest()
    var day: String?
    for change in changes {
        let heading = change.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        if heading != day {
            let count = changes.filter { Calendar.current.isDate($0.date, inSameDayAs: change.date) }.count
            print("\(heading) — \(count) change\(count == 1 ? "" : "s")")
            day = heading
        }
        let time = change.date.formatted(date: .omitted, time: .shortened)
        let status = change.path == nil ? "" : (change.stillInstalled ? "  [still installed]" : "  [gone]")
        let known = change.item(in: inventory).map { "  [in audit: \($0.stateTitle)]" } ?? ""
        print("  \(pad(time, 10))\(pad(change.title, 40))\(change.detail)\(status)\(known)")
    }
    print("\(changes.count) entries")
    exit(0)
}

func probeNetwork(_ args: [String]) -> Never {
    let url = option("--log", in: args).map { URL(fileURLWithPath: $0) } ?? AnalyzersPaths.networkLog
    let runs = NetworkSnapshotHistory.read(at: url)
    guard let newest = runs.first else { print("no snapshots in \(url.path)"); exit(1) }
    if args.contains("--history") {
        for run in runs {
            print("\(run.date.formatted(date: .abbreviated, time: .shortened))  ↓ \(ByteSize.format(run.totalDownloaded))"
                  + "  ↑ \(ByteSize.format(run.totalUploaded))  \(run.processCount) processes  busiest: \(run.busiest ?? "-")")
        }
        exit(0)
    }
    let groups = NetworkGroup.groups(of: newest.rows(resolving: true, census: MemoryCensus.take()))
    print("Snapshot \(newest.date.formatted(date: .abbreviated, time: .shortened)) · ↓ \(ByteSize.format(newest.totalDownloaded))"
          + " · ↑ \(ByteSize.format(newest.totalUploaded)) · \(newest.processCount) programs in \(groups.count) apps · \(runs.count) saved")
    print(pad("APP / PROGRAM", 30) + pad("TOTAL", 10) + pad("DOWN", 10) + pad("UP", 10) + pad("SHARE", 7) + "KIND")
    for group in groups {
        if group.count == 1, let row = group.rows.first {
            print("  " + pad(row.name, 28) + pad(ByteSize.format(row.total), 10) + pad(ByteSize.format(row.downloaded), 10)
                  + pad(ByteSize.format(row.uploaded), 10) + pad("\(Int((row.share * 100).rounded()))%", 7) + row.kindTitle)
        } else {
            print("▸ " + pad(group.name, 28) + pad(ByteSize.format(group.total), 10) + pad(ByteSize.format(group.downloaded), 10)
                  + pad(ByteSize.format(group.uploaded), 10) + pad("\(Int((group.share * 100).rounded()))%", 7) + group.countText)
            for row in group.rows {
                print("      " + pad(row.name, 24) + pad(ByteSize.format(row.total), 10) + pad(ByteSize.format(row.downloaded), 10)
                      + pad(ByteSize.format(row.uploaded), 10) + pad("\(Int((row.share * 100).rounded()))%", 7) + "pid \(row.pid)")
            }
        }
    }
    let problems = NetworkGroup.problems(in: groups)
    print(problems.isEmpty ? "levels: ok" : "levels: PROBLEMS\n" + problems.map { "  " + $0 }.joined(separator: "\n"))
    exit(problems.isEmpty ? 0 : 1)
}

func probeReports(_ args: [String]) -> Never {
    let reports = ReportLibrary.all()
    var problems: [String] = []
    for kind in ReportDocument.Kind.allCases {
        let ofKind = reports.filter { $0.kind == kind }
        let days = ReportMonth.months(of: ofKind)
        print("\(kind.title) — \(ofKind.count) in \(days.count) months")
        for day in days {
            print("  \(day.date.formatted(.dateTime.month(.wide).year())) — \(day.summary)")
            for report in day.reports { print("      \(pad(report.displayName, 40))\(ByteSize.format(report.fileSize))") }
            let names = day.reports.map(\.displayName)
            for name in Set(names) where names.filter({ $0 == name }).count > 1 { problems.append("\(name) appears twice in one month") }
        }
    }
    if !reports.isEmpty, ReportDocument.Kind.allCases.contains(where: { kind in reports.allSatisfy { $0.kind == kind } }) {
        print("(only one kind of report exists on this Mac)")
    }
    if let which = option("--read", in: args).flatMap(Int.init), reports.indices.contains(which),
       let text = reports[which].text() {
        let parts = ReportSection.split(ReportMarkdown.blocks(from: text))
        print("\n--- \(reports[which].displayName): \(parts.preface.count) opening blocks, \(parts.sections.count) sections ---")
        for section in parts.sections {
            let tables = section.blocks.filter { if case .table = $0 { true } else { false } }.count
            print("  \(pad(section.title, 52)) \(section.blocks.count) blocks, \(tables) tables")
        }
    }
    print(problems.isEmpty ? "levels: ok" : "levels: PROBLEMS\n" + problems.map { "  " + $0 }.joined(separator: "\n"))
    exit(problems.isEmpty ? 0 : 1)
}
