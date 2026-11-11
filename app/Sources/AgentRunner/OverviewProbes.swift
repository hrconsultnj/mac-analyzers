import Foundation
@_spi(TestSupport) import AnalyzersKit

// Headless proofs for the Overview track: what Trends totals, the Undo history,
// Overview and the menu-bar panel will say, from the real Mac, read only.

// `agent-runner --probe-trends [days]` prints the totals Trends shows, from
// the real logs (read only): disk reclaimed over the period, as the screen used
// to read it (last 256 KB, newest 20 runs) and as it reads it now (every run).
func probeTrends(_ args: [String]) {
    let days = args.dropFirst().first.flatMap(Double.init) ?? 30
    let interval = days * 86_400
    let before = TrendTotals.diskReclaimed(within: interval, wholeFile: false)
    let started = Date()
    let after = TrendTotals.diskReclaimed(within: interval, wholeFile: true)
    let memoryStarted = Date()
    let reaped = TrendTotals.reapedMemoryMB(within: interval)
    let elapsed = Date().timeIntervalSince(started), memoryElapsed = Date().timeIntervalSince(memoryStarted)
    print("Disk reclaimed, last \(Int(days)) days")
    // the screen's old reading: a date only at the very start of the run header
    let legacy = DateFormatter(); legacy.dateFormat = "yyyy-MM-dd HH:mm"; legacy.locale = Locale(identifier: "en_US_POSIX")
    let legacySeen = LogParser.runs(for: .storageClean).filter { legacy.date(from: String($0.header.prefix(16))) != nil }.count
    print("  as the screen read it before: \(legacySeen) runs had a date it could find, so 0 KB")
    print("  newest 20 runs only, date found: \(before.runsInPeriod) runs seen, \(before.runs.count) freed space, \(ByteSize.format(before.freedBytes))")
    print("  whole log, date found:        \(after.runsInPeriod) runs seen, \(after.runs.count) freed space, \(ByteSize.format(after.freedBytes))")
    print("Memory closed by the cleaners, same period: \(MemorySize.text(Int64(reaped) * 1_048_576))")
    print("Cost of the whole-log reads: disk \(String(format: "%.2f", elapsed - memoryElapsed)) s, memory \(String(format: "%.2f", memoryElapsed)) s (logs: \(AnalyzersPaths.storageAutoCleanLog.lastPathComponent) \((try? FileManager.default.attributesOfItem(atPath: AnalyzersPaths.storageAutoCleanLog.path)[.size] as? Int).map { $0 / 1024 } ?? 0) KB)")
    print("STORAGE tab — deleted by project (level 3), biggest first:")
    for group in after.groups.prefix(6) {
        print("    \(group.project)  —  \(group.items) \(group.items == 1 ? "item" : "items") · \(ByteSize.format(group.bytes))")
    }
    print("    … \(after.groups.count) projects in all, \(ByteSize.format(after.freedBytes)) freed in \(after.runs.count) runs")
    for run in after.runs.prefix(40) {
        print("    \(run.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))  \(run.mode)  \(ByteSize.format(run.deletedBytes))  — \(run.summary ?? "no summary")")
    }
    exit(0)
}


// `agent-runner --probe-undo` prints the Undo history as the screen groups it
// (real receipts and guard log, read only): days, their summaries, and each
// entry's name, outcome, who, when and whether it can be restored.
func probeUndo(_ args: [String]) {
    let now = Date()
    let started = Date()
    let entries = UndoHistory.entries(now: now)
    let took = Date().timeIntervalSince(started)
    print("TIME  \(entries.count) entries read in \(String(format: "%.1f", took)) s (receipts of two logs, their dates, and the guard log)")
    var problems: [String] = []
    for scope in UndoEntry.Scope.allCases {
        let inScope = entries.filter { $0.scope == scope }
        print("\(scope == .trashed ? "MOVED TO THE TRASH" : "STOPPED DEV SERVERS")   (\(inScope.count))")
        for day in UndoHistory.days(inScope).prefix(4) {
            print("  \(day.title(now: now))   — \(day.summary)")
            for run in day.runs.prefix(5) {
                let time = run.when?.formatted(.dateTime.hour().minute()) ?? "--:--"
                print("    ▸ \(run.by) · \(time)   \(run.summary)")
                for child in run.children.prefix(3) { print("        \(child.title) — \(child.outcome)") }
                if run.children.count > 3 { print("        … and \(run.children.count - 3) more rows") }
                // a title repeating inside a group tells a person nothing apart
                let titles = run.children.map(\.title)
                if Set(titles).count < titles.count, run.count > 1 {
                    let repeated = Dictionary(grouping: titles, by: { $0 }).filter { $0.value.count > 1 }.keys
                    problems.append("run \(run.by) \(time): repeated title \(repeated.sorted().prefix(3))")
                }
            }
        }
    }
    for problem in problems { print("NOTE: \(problem)") }
    print("\(entries.count) entries (\(entries.filter { $0.scope == .trashed }.count) moved to the Trash, \(entries.filter { $0.scope == .stopped }.count) stopped)")
    exit(0)
}


// `agent-runner --probe-overview` prints what Overview will say from the real
// Mac (read only): the three tiles, what needs attention, and the latest guard
// events as named rows.
func probeOverview(_ args: [String]) {
    let engine = EngineStatus.probe()
    // as the screen reads them: after the Clear floor, if there is one
    let allEvents = GuardLogParser.recentEvents(fromLog: AnalyzersPaths.guardLog, limit: 8)
    let events = GuardLogParser.recentEvents(fromLog: AnalyzersPaths.guardLog, limit: 8, after: OverviewModel.eventsClearedAt())
    let model = OverviewModel(.init(
        pressure: LiveStats.memoryPressure(), engine: engine,
        killsToday: GuardLogParser.killsToday(fromLog: AnalyzersPaths.guardLog),
        disk: LiveStats.diskUsage(), runwayText: nil, runwayUrgent: false, reclaimableBytes: 2 << 30,
        thermalElevated: false, update: (true, "9.9.9", UpdateChecker.installedVersion), events: events))
    print("TILES")
    for tile in model.tiles { print("  \(tile.value)  —  \(tile.caption)   [opens \(tile.target)]") }
    print("NEEDS ATTENTION (pressure, guard and update are real; the update and the 2 GB reclaimable are fixtures)")
    for item in model.attention {
        switch item.action {
        case .open(let target): print("  \(item.title)  —  \(item.detail)   [opens \(target)]")
        case .resumeGuard: print("  \(item.title)  —  \(item.detail)   [Resume]")
        }
    }
    let now = Date()
    let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"; stamp.timeZone = .current
    print("CLOCK  now \(stamp.string(from: now)); the log's events are local time and \"recent\" is the last 24 hours, not a calendar day")
    print("CLEARED  \(OverviewModel.eventsClearedAt().map { stamp.string(from: $0) } ?? "never") — events before this are hidden from Overview and the menu panel (the Clear button), not from the log")
    print("RECENT EVENTS (\(events.count) shown; \(allEvents.count) in the last 24 hours in the log, newest \(allEvents.first.map { stamp.string(from: $0.date) } ?? "none"))")
    for row in model.events { print("  \(row.when.formatted(.dateTime.hour().minute()))  \(row.title)  —  \(row.outcome)") }
    // the screen's own formula (`TrendsModel.snapshot(.day7)`): guard stops, what their processes held, plus what the cleaners closed
    let week = 7.0 * 86_400
    let weekEvents = GuardLogParser.allEvents(fromLog: AnalyzersPaths.guardLog, within: week)
    let stops = weekEvents.filter(\.isKill)
    let disk = TrendTotals.diskReclaimed(within: week)
    let memoryMB = stops.compactMap(\.residentMB).reduce(0, +) + TrendTotals.reapedMemoryMB(within: week)
    print("THIS WEEK  \(OverviewModel.Week(stopped: stops.count, alerts: weekEvents.count - stops.count, freedBytes: disk.freedBytes, memoryFreedMB: memoryMB, runs: disk.runsInPeriod).summary)")
    print("RECLAIMABLE  \(TrendTotals.latestPreview().map { ByteSize.format($0.bytes) } ?? "nothing shown — the newest storage run was an apply (or there is none)")")
    exit(0)
}


// `agent-runner --probe-menu` prints the process list the menu-bar panel will
// show: the census's groups, names and footprint numbers, biggest first, no
// size floor — the same as Monitor's first rows.
func probeMenu(_ args: [String]) {
    let census = MemoryCensus.take()
    let panel = MenuPanelModel(census: census)
    print("Processes  (\(panel.totalGroups) groups hold \(MemorySize.text(panel.totalBytes)))")
    for row in panel.processes {
        let pad = String(repeating: " ", count: max(0, 9 - row.sizeText.count))
        print("  \(pad)\(row.sizeText)  \(row.name)\(row.detail.map { "  —  \($0)" } ?? "")\(row.canQuit ? "" : "  [part of macOS]")")
    }
    print("  and \(panel.totalGroups - panel.processes.count) more in \(Names.Screen.monitor)")
    print("Monitor's first rows for comparison (same census):")
    for group in census.groups.prefix(3) { print("  \(group.totalText)  \(group.name)") }
    exit(0)
}



// `agent-runner --probe-undo-fixture` builds its own scratch folder (receipts and
// a fake Trash — never the real Trash or the real logs), runs every way a restore
// can go wrong, and exits non-zero on any failure. It is the safe test for the
// code that moves real files.
/// The probe's clock. `--second S` reads as that second of the current minute, so anything that depends on
/// where in a minute the probe starts (the logs' banners are minute-precise) can be proven at any second.
private func probeClock(_ args: [String]) -> Date {
    let real = Date()
    guard let at = args.firstIndex(of: "--second"), args.indices.contains(at + 1), let second = Double(args[at + 1]) else { return real }
    return Date(timeIntervalSince1970: (real.timeIntervalSince1970 / 60).rounded(.down) * 60 + second)
}

func probeUndoFixture(_ args: [String]) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "ma-undo-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
    let trash = root.appending(path: "Trash"), work = root.appending(path: "work")
    try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
    try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    var failures = 0
    var step = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        step += 1
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(String(format: "%2d", step)). \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
    func write(_ text: String, to url: URL) { try? text.write(to: url, atomically: true, encoding: .utf8) }
    func touch(_ path: String, _ text: String = "x") {
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: path, contents: Data(text.utf8))
    }
    let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"; stamp.locale = Locale(identifier: "en_US_POSIX")
    func banner(_ date: Date) -> String { "storage-analyzer | mode=fixture | APPLY | \(stamp.string(from: date)) | fixture" }
    func ledger(_ name: String, _ lines: [String]) -> URL {
        let url = root.appending(path: name); write(lines.joined(separator: "\n") + "\n", to: url); return url
    }
    func items(_ url: URL) -> [TrashedItem] { UndoLedger.trashedItems(in: url, source: "Janitor", trash: trash) }
    func id(_ path: String) -> String { ReceiptIdentity.current(of: path).map { "  #id=\($0)" } ?? "" }
    let now = probeClock(args)

    // 1. the identity proves it is the same item — and a later same-name item is refused
    let projA = work.appending(path: "proj/a").path
    let original = projA + "/node_modules", inTrash = trash.path + "/node_modules"
    touch(inTrash, "the cleaner's item")
    let log1 = ledger("one.log", [banner(now), "[TRASHED] 1 KB  \(original)  ->  \(inTrash)\(id(inTrash))"])
    try? fm.createDirectory(atPath: projA, withIntermediateDirectories: true)
    check("a receipt with its identity lists as restorable", items(log1).first?.restorability == .restorable)
    try? fm.removeItem(atPath: inTrash)                       // the Trash is emptied …
    touch(inTrash, "the person's OWN node_modules, trashed later")   // … and a later item takes the name
    let later = items(log1).first
    check("a later item with the same name is not the same item", later?.restorability == .notTheSameItem)
    var refused = false
    if let later { do { try UndoLedger.restore(later, trash: trash) } catch { refused = true } }
    check("restore refuses it, and the person's item stays in the Trash",
          refused && fm.fileExists(atPath: inTrash) && !fm.fileExists(atPath: original))

    // 2. the identity is re-checked at the moment of the click, not only when listed
    let doc = work.appending(path: "doc.txt").path, docTrash = trash.path + "/doc.txt"
    touch(docTrash, "original")
    let log2 = ledger("two.log", [banner(now), "[TRASHED] 1 KB  \(doc)  ->  \(docTrash)\(id(docTrash))"])
    let listed = items(log2).first
    check("listed as restorable", listed?.restorability == .restorable)
    try? fm.removeItem(atPath: docTrash); touch(docTrash, "swapped in after the list was built")
    refused = false
    if let listed { do { try UndoLedger.restore(listed, trash: trash) } catch { refused = true } }
    check("swapped between listing and click: refused", refused && !fm.fileExists(atPath: doc))

    // 3. a restore that is allowed moves the file and writes its receipt once
    let ok = work.appending(path: "ok.txt").path, okTrash = trash.path + "/ok.txt"
    touch(okTrash, "fine")
    let log3 = ledger("three.log", [banner(now), "[TRASHED] 1 KB  \(ok)  ->  \(okTrash)\(id(okTrash))"])
    var result: UndoLedger.Restored?
    if let item = items(log3).first { result = try? UndoLedger.restore(item, trash: trash) }
    let receipts = ((try? String(contentsOf: log3, encoding: .utf8)) ?? "").components(separatedBy: "[RESTORED]").count - 1
    check("an item that is the same is restored, with one receipt",
          fm.fileExists(atPath: ok) && !fm.fileExists(atPath: okTrash) && receipts == 1 && result?.receiptWritten == true)
    check("once restored it is no longer offered", items(log3).isEmpty)
    // a second click on a stale row
    check("a second restore of the same item is refused (nothing in the Trash)", {
        let again = TrashedItem(originalPath: ok, ledger: log3, source: "Janitor", trashPath: okTrash, sizeText: "1 KB",
                                restorability: .restorable, identity: nil, receiptDate: now)
        do { try UndoLedger.restore(again, trash: trash); return false } catch { return true }
    }())

    // 4. a receipt that names a place outside the Trash, or a path with ..
    let secret = work.appending(path: "important.txt").path, elsewhere = work.appending(path: "elsewhere.txt").path
    touch(secret, "must not move")
    let log4 = ledger("four.log", [banner(now), "[TRASHED] 1 KB  \(elsewhere)  ->  \(secret)"])
    check("a Trash path outside the Trash is unsafe", items(log4).first?.restorability == .unsafePath)
    let log4b = ledger("four-b.log", [banner(now), "[TRASHED] 1 KB  \(work.path)/proj/../../escape  ->  \(trash.path)/x"])
    check("an original path with .. is unsafe", items(log4b).first?.restorability == .unsafePath)
    let link = trash.path + "/linked"
    try? fm.createSymbolicLink(atPath: link, withDestinationPath: work.path)
    let log4c = ledger("four-c.log", [banner(now), "[TRASHED] 1 KB  \(work.path)/out  ->  \(link)/important.txt"])
    check("a path that leaves the Trash through a symlink is unsafe", items(log4c).first?.restorability == .unsafePath)
    check("nothing was moved by any of them", fm.fileExists(atPath: secret) && !fm.fileExists(atPath: elsewhere))

    // 5. a family: every destination is checked before any member moves
    let dir = work.appending(path: "family").path, folder = trash.path + "/temp-clean-family"
    touch(folder + "/a"); touch(folder + "/b"); touch(folder + "/c")
    touch(dir + "/b", "already here")                          // one member's old place is taken
    let log5 = ledger("five.log", [banner(now), "[TRASHED] 3 KB  \(dir)/fam*  ->  \(folder)\(id(folder))"])
    let family = items(log5).first
    check("a family with one destination taken is not restorable", family?.restorability == .pathOccupied)
    refused = false
    if let family { do { try UndoLedger.restore(family, trash: trash) } catch { refused = true } }
    check("it moved NONE of its members", refused && !fm.fileExists(atPath: dir + "/a") && fm.fileExists(atPath: folder + "/a"))
    try? fm.removeItem(atPath: dir + "/b")
    var done: UndoLedger.Restored?
    if let family = items(log5).first { done = try? UndoLedger.restore(family, trash: trash) }
    let text5 = (try? String(contentsOf: log5, encoding: .utf8)) ?? ""
    check("with room, all three members are restored: a member line each (own tag, no size) and the family's one pairing line",
          ["a", "b", "c"].allSatisfy { fm.fileExists(atPath: dir + "/\($0)") } && done?.members == 3
          && text5.components(separatedBy: "[RESTORED·member]").count - 1 == 3
          && text5.components(separatedBy: "[RESTORED] ").count - 1 == 1)

    // 6. the folder it came from is gone
    let gone = work.appending(path: "vanished/file.txt").path, goneTrash = trash.path + "/file.txt"
    touch(goneTrash)
    let log6 = ledger("six.log", [banner(now), "[TRASHED] 1 KB  \(gone)  ->  \(goneTrash)\(id(goneTrash))"])
    check("the parent folder is gone: not restorable, with a reason", items(log6).first?.restorability == .parentGone)

    // 7. a receipt that cannot be written is reported, not hidden
    let sealed = work.appending(path: "sealed.txt").path, sealedTrash = trash.path + "/sealed.txt"
    touch(sealedTrash)
    let log7 = ledger("seven.log", [banner(now), "[TRASHED] 1 KB  \(sealed)  ->  \(sealedTrash)\(id(sealedTrash))"])
    try? fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: log7.path)
    var sealedResult: UndoLedger.Restored?
    if let item = items(log7).first { sealedResult = try? UndoLedger.restore(item, trash: trash) }
    check("the file moved, and the failed receipt write is reported", fm.fileExists(atPath: sealed) && sealedResult?.receiptWritten == false)

    // 8. a RESTORED line answers only the TRASHED line before it
    let again = work.appending(path: "again.txt").path, againTrash = trash.path + "/again.txt"
    touch(againTrash)
    let log8 = ledger("eight.log", [banner(now), "[TRASHED] 1 KB  \(again)  ->  \(trash.path)/old\(id(againTrash))",
                                    "[RESTORED] 1 KB  \(again)", banner(now),
                                    "[TRASHED] 1 KB  \(again)  ->  \(againTrash)\(id(againTrash))"])
    check("trashed, restored, then trashed again: the second one is still offered", items(log8).count == 1)

    // 9. a receipt without an identity (all written so far) needs the item to have entered the Trash with the run
    let old = work.appending(path: "old.txt").path, oldTrash = trash.path + "/old.txt"
    touch(oldTrash)
    let hourAgo = now.addingTimeInterval(-3600)
    let log9 = ledger("nine.log", [banner(hourAgo), "[TRASHED] 1 KB  \(old)  ->  \(oldTrash)"])
    check("no identity and the item arrived long after the run: cannot verify", items(log9).first?.restorability == .cannotVerify)
    let log9b = ledger("nine-b.log", [banner(now), "[TRASHED] 1 KB  \(old)  ->  \(oldTrash)"])
    check("no identity and the item arrived with the run: restorable", items(log9b).first?.restorability == .restorable)
    let log9c = ledger("nine-c.log", ["[TRASHED] 1 KB  \(old)  ->  \(oldTrash)"])
    check("no identity and no run date at all: cannot verify", items(log9c).first?.restorability == .cannotVerify)

    // 11. a folder on the way to the original place has been replaced by a link
    let real = work.appending(path: "real-dir").path, linked = work.appending(path: "linked-dir").path
    try? fm.createDirectory(atPath: real, withIntermediateDirectories: true)
    try? fm.createSymbolicLink(atPath: linked, withDestinationPath: "elsewhere-dir")
    let elsewhereDir = work.appending(path: "elsewhere-dir").path
    try? fm.createDirectory(atPath: elsewhereDir, withIntermediateDirectories: true)
    try? fm.removeItem(atPath: linked)
    try? fm.createSymbolicLink(atPath: linked, withDestinationPath: elsewhereDir)
    let redir = linked + "/d.bin", redirTrash = trash.path + "/d.bin"
    touch(redirTrash)
    let log11 = ledger("eleven.log", [banner(now), "[TRASHED] 1 KB  \(redir)  ->  \(redirTrash)\(id(redirTrash))"])
    check("a linked folder in the original path: not restorable, with a reason", items(log11).first?.restorability == .parentRedirected)
    if let item = items(log11).first { _ = try? UndoLedger.restore(item, trash: trash) }
    check("nothing landed in the folder the link points to", !fm.fileExists(atPath: elsewhereDir + "/d.bin") && fm.fileExists(atPath: redirTrash))

    // 12. a family's member lines never answer an unrelated receipt for the same path
    let fdir = work.appending(path: "fam2").path, ffolder = trash.path + "/temp-clean-fam2", other = trash.path + "/m-single"
    touch(ffolder + "/m"); touch(other)
    try? fm.createDirectory(atPath: fdir, withIntermediateDirectories: true)
    let log12 = ledger("twelve.log", [banner(now),
        "[TRASHED] 1 KB  \(fdir)/m  ->  \(other)\(id(other))",       // a single item with the member's path
        "[TRASHED] 2 KB  \(fdir)/fam*  ->  \(ffolder)\(id(ffolder))"])
    let listed12 = items(log12)
    if let family = listed12.first(where: { $0.isGroup }) { _ = try? UndoLedger.restore(family, trash: trash) }
    let after12 = items(log12)
    check("after the family is restored, the unrelated single receipt is still listed",
          after12.contains { $0.originalPath == fdir + "/m" } && !after12.contains { $0.isGroup })

    // 13. an old receipt does not trust a link that sits in the Trash slot
    let slot = trash.path + "/slot.txt", victim = work.appending(path: "victim.txt").path
    touch(victim, "not the cleaner's")
    try? fm.createSymbolicLink(atPath: slot, withDestinationPath: victim)
    let log13 = ledger("thirteen.log", [banner(now), "[TRASHED] 1 KB  \(work.path)/slot.txt  ->  \(slot)"])
    check("no identity and a link in the Trash slot: cannot verify", items(log13).first?.restorability == .cannotVerify)

    // 14. a group that fails part-way puts back the members it moved and writes no RESTORED receipt
    let rdir = work.appending(path: "rollback").path, rfolder = trash.path + "/temp-clean-rollback"
    for name in ["m1", "m2", "m3", "m4", "m5"] { touch(rfolder + "/" + name) }
    try? fm.createDirectory(atPath: rdir, withIntermediateDirectories: true)
    let log14 = ledger("fourteen.log", [banner(now), "[TRASHED] 5 KB  \(rdir)/fam*  ->  \(rfolder)\(id(rfolder))"])
    try? fm.setAttributes([.immutable: true], ofItemAtPath: rfolder + "/m3")      // this one cannot be moved
    var rolledBack = false
    if let family = items(log14).first { do { try UndoLedger.restore(family, trash: trash) } catch { rolledBack = true } }
    try? fm.setAttributes([.immutable: false], ofItemAtPath: rfolder + "/m3")
    let text14 = (try? String(contentsOf: log14, encoding: .utf8)) ?? ""
    check("a failed family restore: every member is back in the Trash and nothing was receipted",
          rolledBack && ["m1", "m2", "m3", "m4", "m5"].allSatisfy { fm.fileExists(atPath: rfolder + "/" + $0) && !fm.fileExists(atPath: rdir + "/" + $0) }
          && !text14.contains("[RESTORED"))

    // 10. the identity suffix never leaks into what other readers show
    let line = "[TRASHED] 2.0 GB  /Users/x/Downloads/big.zip  ->  /Users/x/.Trash/big.zip  #id=16777234:12345"
    let storage = StorageCleanParser.parse(runHeader: "janitor | APPLY", lines: ["### Downloads", line])
    check("the storage parser's path has no suffix", storage.items.first.map { !$0.path.contains("#id=") } ?? false,
          storage.items.first?.path ?? "no item")
    let temp = TempCleanParser.parse(runHeader: "temp | APPLY", lines: ["### Temporary files", line])
    check("the temp parser's destination has no suffix", temp.items.first?.destination?.contains("#id=") == false,
          temp.items.first?.destination ?? "no item")
    check("an old receipt (no suffix) still parses", ReceiptIdentity.split("/a  ->  /b").id == nil)

    // 11. a restore writes ONE block of its own, in the shape the log's other blocks have
    let rule = String(repeating: "=", count: 64)
    let clock = DateFormatter(); clock.dateFormat = "yyyy-MM-dd HH:mm"; clock.locale = Locale(identifier: "en_US_POSIX")
    func janitorBanner(_ date: Date, _ mode: String) -> String {
        "\(clock.string(from: date)) | downloads janitor | \(mode) | downloads>30d screenshots>14d"
    }
    func trashedLine(_ tag: String) -> (original: String, line: String) {
        let original = work.appending(path: "r11/\(tag)/file-\(tag)").path
        let inTrash = trash.path + "/r11-\(tag)"
        touch(inTrash, "item \(tag)")
        try? fm.createDirectory(atPath: (original as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        return (original, "[TRASHED] 1 KB  \(original)  ->  \(inTrash)\(id(inTrash))")
    }
    func restoreBanners(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            .filter { RestoreBlock.isRestore(header: $0) }
    }
    func shape(_ runs: [LogRun]) -> [String] { runs.map { $0.header + "\n" + $0.lines.joined(separator: "\n") } }
    let previewAt = now.addingTimeInterval(-3600)
    let previewBanner = janitorBanner(previewAt, "DRY RUN")
    let a = trashedLine("a"), b = trashedLine("b"), c = trashedLine("c"), d = trashedLine("d")
    let logJ = ledger("janitor.log", [
        rule, janitorBanner(now.addingTimeInterval(-7200), "APPLY"), "### Downloads",
        a.line, b.line, c.line, d.line,
        rule, previewBanner, "### Downloads",
        "[DRY] 2.0 MB  /Users/x/Downloads/p1.zip", "[DRY] 3.0 MB  /Users/x/Downloads/p2.zip",
        "[DRY] 4.0 MB  /Users/x/Downloads/p3.zip", "DRY RUN — would move 3 item(s), 9.0 MB, to the Trash. Re-run with --apply.",
    ])
    let runsBefore = shape(LogParser.runs(at: logJ))
    let summariesBefore = LogParser.runs(at: logJ).map { ActivitySummary.of($0, in: .janitor).text }
    let wholeBefore = WholeRun.find(banner: previewBanner, in: logJ)
    let listedBefore = items(logJ).count
    let wanted = items(logJ).filter { [a.original, b.original, c.original].contains($0.originalPath) }
    let first = UndoLedger.restore(wanted, trash: trash)
    check("a restore of three items put all three back", first.restored == 3 && first.failures.isEmpty && first.unrecorded == 0,
          "restored \(first.restored), failed \(first.failures.count)")
    let banners = restoreBanners(logJ)
    check("one Restore action wrote one block, however many items", banners.count == 1, "\(banners.count) restore banners")
    check("its banner is dated to the second and the matcher reads it as a banner",
          banners.first.map { RunDate.parse(banner: $0)?.hasSeconds == true && RunMatcher.banner(in: $0) != nil } ?? false,
          banners.first ?? "no banner")
    let fileLines = ((try? String(contentsOf: logJ, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    let at = fileLines.firstIndex { RestoreBlock.isRestore(header: $0) } ?? -1
    check("the block is a rule, the banner, a rule, then the lines",
          at > 0 && at + 1 < fileLines.count && fileLines[at - 1].allSatisfy { $0 == "=" } && fileLines[at + 1].allSatisfy { $0 == "=" })
    let restoredLines = fileLines.filter { $0.hasPrefix("[RESTORED]") }
    check("the block holds one receipt line per item", restoredLines.count == 3, "\(restoredLines.count) lines")

    // 12. the ledger pairing does not depend on the block
    let after = items(logJ)
    check("a receipt answers its trashed line across the new banner: only the unrelated item is still offered",
          after.count == listedBefore - 3 && after.first?.originalPath == d.original, "\(after.count) listed")
    let aged = trashedLine("old")
    let logOld = ledger("old-bannerless.log", [rule, janitorBanner(now.addingTimeInterval(-9000), "APPLY"), "### Downloads",
                                              aged.line, "[RESTORED] 1 KB  \(aged.original)"])
    check("an old log with a bannerless receipt still pairs it", items(logOld).isEmpty, "\(items(logOld).count) listed")

    // 13. no other run changes because a restore came after it
    check("the runs the log lists are the same lines, in the same order", shape(LogParser.runs(at: logJ)) == runsBefore)
    check("each run's own result sentence is the same",
          LogParser.runs(at: logJ).map { ActivitySummary.of($0, in: .janitor).text } == summariesBefore,
          "\(LogParser.runs(at: logJ).map { ActivitySummary.of($0, in: .janitor).text })")
    let everything = LogParser.runs(at: logJ, includingRestores: true)
    check("asked for, the restore is the newest run and holds its three receipts",
          everything.first.map { RestoreBlock.isRestore(header: $0.header) && RestoreBlock.items(in: $0.lines).count == 3 } ?? false)
    if case .block(let block)? = Optional(WholeRun.find(banner: previewBanner, in: logJ)),
       case .block(let was) = wholeBefore {
        let leaked = block.lines.contains { $0.hasPrefix("[RESTORED") }
        let bare = { (lines: [String]) in lines.filter { !$0.allSatisfy { $0 == "=" } } }   // a run is followed by its successor's rule
        check("the matcher still finds the preview's own block, without the restore's lines",
              bare(block.lines) == bare(was.lines) && !leaked)
    } else {
        check("the matcher still finds the preview's own block", false)
    }
    let outcome = RunMatcher.outcome(kind: .janitor, in: logJ, header: previewBanner, startedAt: previewAt)
    var parsedItems = -1
    if case .storage(let run) = outcome.parsed { parsedItems = run.items.count }
    check("a job that wrote the preview still gets its own block back", outcome.match == .exact && parsedItems == 3,
          "\(parsedItems) items")

    // 14. Activity lists the restore as its own row
    let snapshot = LiveJobSnapshot(id: UUID(), kind: .janitor, intent: .preview, trigger: .user, status: .done,
                                   started: previewAt, finished: now.addingTimeInterval(-60), runHeader: previewBanner,
                                   summary: ActivitySummary("Found 3 items", review: "Found 3 items — waiting for your review", findings: 3))
    func rows(_ url: URL, live: [LiveJobSnapshot]) -> [ActivityRow] {
        ActivityJoin.rows(live: live, index: [],
                          logs: [ActivityJoin.LogRuns(log: .janitor, runs: LogParser.runs(at: url, includingRestores: true))],
                          now: now, modified: { _ in nil }, hasOutput: { _ in true },
                          titleForKind: { $0.rawValue }, titleForLog: { $0.rawValue })
    }
    let seen14 = rows(logJ, live: [snapshot])
    let restoreRow = seen14.first { $0.isRestore }
    let restoreFacts: Bool = {
        guard let row = restoreRow else { return false }
        let named = row.title == Names.Screen.undo
        let started = row.trigger == .you && row.status == .done
        return named && started && row.kind == nil
    }()
    check("the restore is a row of its own, started by you, done, named for Undo", restoreFacts,
          restoreRow.map { "\($0.title) / \($0.trigger) / \($0.status)" } ?? "no restore row")
    check("it says what it did, from the name table", restoreRow?.result == "Restored 3 Items", restoreRow?.result ?? "none")
    let restoreQuiet: Bool = {
        guard let row = restoreRow else { return false }
        let nothing = row.freedBytes == 0 && row.findings == 0
        return nothing && !row.needsReview && row.intent == .apply
    }()
    check("it frees and finds nothing, and is never waiting for review", restoreQuiet)
    check("a preview waiting for review stays waiting although a restore came after it",
          seen14.first { $0.header == previewBanner }?.needsReview == true)
    if let run = everything.first {
        let screen = ActivityOutcome.make(.none, run: run, log: .janitor)
        check("its screen lists the three items it put back",
              screen.sections.count == 1 && screen.sections[0].title == Names.Restore.putBack && screen.sections[0].items.count == 3,
              "\(screen.sections.map { "\($0.title) \($0.items.count)" })")
    } else {
        check("its screen lists the items it put back", false)
    }

    // 15. two runs with the same minute-precision banner, a restore between them
    // minute-precise banners: the twins' minute and the job's start are fixed inside one minute, not read off the clock
    let twinAt = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60 - 300)
    let twin = janitorBanner(twinAt, "APPLY")
    let t1 = trashedLine("t1"), t3 = trashedLine("t3")
    let firstRun = [rule, twin, "### Downloads", t1.line, "[TRASHED] 1 KB  /x/never  ->  /x/never2"]
    let secondRun = [rule, twin, "### Downloads", t3.line, "[TRASHED] 2 KB  /x/other  ->  /x/other2"]
    let logT = ledger("twins.log", firstRun)
    let plainT = ledger("twins-without-restore.log", firstRun + secondRun)
    _ = UndoLedger.restore(items(logT).filter { $0.originalPath == t1.original }, trash: trash)
    if let handle = try? FileHandle(forWritingTo: logT) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((secondRun.joined(separator: "\n") + "\n").utf8))
        try? handle.close()
    }
    check("the log with a restore between the twins reads as the log without it",
          shape(LogParser.runs(at: logT)) == shape(LogParser.runs(at: plainT)),
          "\(LogParser.runs(at: logT).count) runs vs \(LogParser.runs(at: plainT).count)")
    let twinsPlain = Set(rows(plainT, live: []).map(\.id))
    let twinsWith = rows(logT, live: [])
    check("every row the plain log has keeps its id, and the restore is one more row",
          twinsPlain == Set(twinsWith.filter { !$0.isRestore }.map(\.id)) && twinsWith.filter { $0.isRestore }.count == 1,
          "\(twinsWith.count) rows")
    if case .block(let last) = WholeRun.find(banner: twin, in: logT, notBefore: twinAt.addingTimeInterval(10)) {
        let ownLine = last.lines.contains { $0.contains(t3.original) }
        let foreign = last.lines.contains { $0.contains(t1.original) || $0.hasPrefix("[RESTORED") }
        check("the matcher takes the LAST twin, with its own lines and none of the restore's", ownLine && !foreign)
    } else {
        check("the matcher takes the last twin", false)
    }
    if case .block(let early) = WholeRun.find(banner: twin, in: ledger("twins-first.log", firstRun + [rule, RestoreBlock.banner(at: now), rule, "Put back 1 item(s)", "[RESTORED] 1 KB  \(t1.original)"]),
                                              notBefore: twinAt.addingTimeInterval(10)) {
        check("a restore after the only twin is not part of it", !early.lines.contains { $0.hasPrefix("[RESTORED") })
    } else {
        check("a restore after the only twin is not part of it", false)
    }

    // 16. one action over items of two cleaners writes one block in each log
    let e = trashedLine("e"), f = trashedLine("f"), g = trashedLine("g")
    let logP = ledger("cleaner-one.log", [rule, janitorBanner(now.addingTimeInterval(-500), "APPLY"), "### Downloads", e.line, f.line])
    let logQ = ledger("cleaner-two.log", [rule, janitorBanner(now.addingTimeInterval(-400), "APPLY"), "### Temporary files", g.line])
    let both = UndoLedger.restore(items(logP) + items(logQ), trash: trash)
    check("an action over two logs writes one block in each, and all three came back",
          both.restored == 3 && restoreBanners(logP).count == 1 && restoreBanners(logQ).count == 1,
          "\(both.restored) restored, \(restoreBanners(logP).count) + \(restoreBanners(logQ).count) blocks")

    // 17. a report-style log (temp-clean's shape: a rule, the banner, a rule, the body, a closing summary)
    let secs = DateFormatter(); secs.dateFormat = "yyyy-MM-dd HH:mm:ss"; secs.locale = Locale(identifier: "en_US_POSIX")
    func tempRun(_ at: Date, _ lines: [String]) -> [String] {
        [rule, " temp-clean  |  APPLY — to Trash  |  \(secs.string(from: at))", rule] + lines
            + ["", rule, " DONE — moved \(lines.count) item(s), 2 KB, to the Trash (recoverable).", rule]
    }
    let h1 = trashedLine("h1"), h2 = trashedLine("h2")
    let runA = tempRun(now.addingTimeInterval(-900), ["### Temporary files", h1.line])
    let runB = tempRun(now.addingTimeInterval(120), ["### Temporary files", h2.line])   // after the restore, which is stamped when it runs
    let logR = ledger("temp-shape.log", runA)
    let plainR = ledger("temp-shape-without-restore.log", runA + runB)
    _ = UndoLedger.restore(items(logR).filter { $0.originalPath == h1.original }, trash: trash)
    if let handle = try? FileHandle(forWritingTo: logR) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((runB.joined(separator: "\n") + "\n").utf8))
        try? handle.close()
    }
    check("a report-style log with a restore between its runs lists its own two runs exactly as it would without it",
          shape(LogParser.runs(at: logR)) == shape(LogParser.runs(at: plainR)) && LogParser.runs(at: logR).count == 2,
          "\(LogParser.runs(at: logR).count) runs")
    let ordered = LogParser.runs(at: logR, includingRestores: true)
    check("asked for, the restore sits between them, newest first",
          ordered.count == 3 && RestoreBlock.isRestore(header: ordered[1].header) && !RestoreBlock.isRestore(header: ordered[0].header),
          ordered.map { RestoreBlock.isRestore(header: $0.header) ? "restore" : "run" }.joined(separator: ", "))
    let temp1 = LogParser.runs(at: logR).last.map { TempCleanParser.parse(runHeader: $0.header, lines: $0.lines).items.count } ?? -1
    check("the run before the restore still parses to its own one item", temp1 == 1, "\(temp1) items")

    // 18. a cleaner's own line that carries a restore banner's words is not a restore
    let sneaky = ["storage-auto-clean.sh  |  mode=daily  |  APPLY  |  \(secs.string(from: now.addingTimeInterval(-50)))",
                  " input: flags: --apply | restore from Undo | APPLY"]
    let logS = ledger("sneaky.log", [rule] + [sneaky[0], sneaky[1], rule, "### Build caches",
                                              "[DELETED] 1.2 GB  /Users/x/Projects/a/.next", "[DELETED] 0.8 GB  /Users/x/Projects/b/.next",
                                              "DONE — deleted 2 item(s), 2.0 GB.", rule])
    let sneakyRuns = LogParser.runs(at: logS, includingRestores: true)
    let sneakyItems = sneakyRuns.first.map { StorageCleanParser.parse(runHeader: $0.header, lines: $0.lines).items.count } ?? -1
    check("a run whose input line carries a restore banner's words is still a run, with its two items",
          sneakyRuns.count == 1 && !RestoreBlock.isRestore(header: sneakyRuns[0].header) && sneakyItems == 2,
          "\(sneakyRuns.count) runs, \(sneakyItems) items")
    check("and it is no restore row in Activity", rows(logS, live: []).filter { $0.isRestore }.isEmpty)
    check("a restore banner is recognised only as its exact shape",
          RestoreBlock.isRestore(header: RestoreBlock.banner(at: now)) && !RestoreBlock.isRestore(header: " input: x | restore from Undo | APPLY")
          && !RestoreBlock.isRestore(header: "2026-11-11 05:12 | restore from Undo | APPLY"))

    try? fm.removeItem(at: root)        // `exit` runs no `defer`
    print(failures == 0 ? "all \(step) checks passed" : "\(failures) of \(step) checks FAILED")
    exit(failures == 0 ? 0 : 1)
}
