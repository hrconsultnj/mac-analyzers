import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-cleanup-parse` ties `cleanup.sh` to the screens that read it: it runs the REAL
// script as a dry run, in a throwaway HOME, against fixture apps and recording folders it makes itself,
// and checks that what it printed is what the Unused Apps and Old Recordings screens turn into rows:
// the banner is a banner, the block is found whole in its own log, each app is a row keyed by its
// bundle's path with its footprint's size, a recording is a row keyed by its folder, and a reviewed list
// that names one app leaves the other as "not in approved set". Nothing outside the temporary folder is
// read or changed, and `--execute` is never passed. Exit 1 when anything differs.

@MainActor func probeCleanupParse() async -> Never {
    let fm = FileManager.default
    // find the script from where this binary lives: <repo>/app/.build/.../AgentRunner
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    var script: URL?
    for _ in 0..<8 {
        let candidate = dir.appending(path: "storage-analyzer/cleanup.sh")
        if fm.fileExists(atPath: candidate.path) { script = candidate; break }
        dir = dir.deletingLastPathComponent()
    }
    guard let script else { print("SKIP: cleanup.sh not found from the binary's location"); exit(0) }
    let repo = script.deletingLastPathComponent().deletingLastPathComponent()

    let root = ProbeScratch.folder("ma-probe-cleanup-parse")
    let home = root.appending(path: "home"), tree = root.appending(path: "tree")
    for folder in ["storage-analyzer", "lib"] { try? fm.createDirectory(at: tree.appending(path: folder), withIntermediateDirectories: true) }
    try? fm.copyItem(at: script, to: tree.appending(path: "storage-analyzer/cleanup.sh"))
    if let libs = try? fm.contentsOfDirectory(at: repo.appending(path: "lib"), includingPropertiesForKeys: nil) {
        for lib in libs { try? fm.copyItem(at: lib, to: tree.appending(path: "lib/\(lib.lastPathComponent)")) }
    }
    var failures = 0, cases = 0
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) { cases += 1; if !ok { failures += 1; print("FAIL  \(what())") } }

    let apps = ["Old Editor", "Screen Recorder"]
    let appPaths = apps.map { home.appending(path: "Applications/\($0).app").path }
    for (index, name) in apps.enumerated() {
        let bundle = home.appending(path: "Applications/\(name).app/Contents")
        try? fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.app\(index)</string></dict></plist>"
        try? plist.write(to: bundle.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
        let support = home.appending(path: "Library/Application Support/\(name)")
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        try? Data(count: 300_000 * (index + 1)).write(to: support.appending(path: "data"))
    }
    for name in ["Old1", "Old2"] {
        let folder = home.appending(path: "Recordings/\(name)")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(count: 200_000).write(to: folder.appending(path: "clip.mov"))
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -400 * 86_400)], ofItemAtPath: folder.path)
    }
    let config = "ANALYZERS_STALE_APPS=( \(appPaths.map { "\"\($0)\"" }.joined(separator: " ")) )\nANALYZERS_RECORDINGS_DIR=\"\(home.path)/Recordings\"\n"
    try? config.write(to: tree.appending(path: "config.local.sh"), atomically: true, encoding: .utf8)

    func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [tree.appending(path: "storage-analyzer/cleanup.sh").path] + arguments
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
    func lines(_ text: String) -> [String] { text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    // the apps preview
    let preview = lines(run(["--stale-apps"]))
    let banner = preview.compactMap { RunMatcher.banner(in: $0) }.first
    expect(banner?.hasPrefix("cleanup | apps | DRY RUN | ") == true, "the apps preview has a banner: \(banner ?? "none")")
    let rows = UnusedReview.apps(lines: preview)
    expect(rows.rows.count == 2, "two apps become two rows, got \(rows.rows.count)")
    expect(Set(rows.rows.map(\.id)) == Set(appPaths), "each row is keyed by its app bundle's path: \(rows.rows.map(\.id))")
    expect(rows.rows.allSatisfy { ($0.bytes ?? 0) > 100_000 }, "each row carries its footprint's size: \(rows.rows.map { $0.bytes ?? -1 })")
    expect(rows.rows.allSatisfy { $0.detail?.contains("Application Support") == true }, "each row names what goes with it: \(rows.rows.compactMap(\.detail))")
    // the block is found whole in its own log, by its banner
    let log = home.appending(path: "mac-analyzers/reports/storage/cleanup-apps.log")
    if let banner, case .block(let block) = WholeRun.find(banner: banner, in: log) {
        expect(UnusedReview.apps(lines: block.lines).rows.count == 2, "the block found in the log gives the same two rows")
    } else { expect(false, "the block was not found in cleanup-apps.log by its banner") }
    expect(appPaths.allSatisfy { fm.fileExists(atPath: $0) }, "a preview removed nothing")

    // a reviewed list naming one app: the other is skipped
    let list = root.appending(path: "list.txt")
    try? (appPaths[0] + "\n").write(to: list, atomically: true, encoding: .utf8)
    let listed = lines(run(["--stale-apps", "--only-paths", list.path]))
    expect(UnusedReview.apps(lines: listed).rows.map(\.id) == [appPaths[0]], "a list of one app previews one row")
    expect(listed.contains { $0.hasPrefix("[SKIP] not in approved set") && $0.contains(appPaths[1]) }, "the other app is said to be skipped")

    // recordings
    let recordings = lines(run(["--recordings-older-than", "30"]))
    expect(recordings.compactMap { RunMatcher.banner(in: $0) }.first?.hasPrefix("cleanup | recordings | DRY RUN | ") == true, "the recordings preview has a banner")
    let recordingRows = UnusedReview.recordings(lines: recordings)
    expect(Set(recordingRows.rows.map(\.id)) == Set(["Old1", "Old2"].map { home.appending(path: "Recordings/\($0)").path }),
           "each recording folder is a row keyed by its path: \(recordingRows.rows.map(\.id))")
    expect(recordingRows.rows.allSatisfy { ($0.bytes ?? 0) > 100_000 && $0.group != Names.Download.dateUnknown }, "each has a size and a month: \(recordingRows.rows.map { "\($0.group ?? "-") \($0.bytes ?? -1)" })")

    // discovery: found apps, kept when they cannot be judged, and what an apply did (to the Trash)
    let found = root.appending(path: "found")
    let foundApps = found.appending(path: "apps"), stubs = found.appending(path: "stubs"), launch = found.appending(path: "launch")
    for folder in [foundApps, stubs, launch, found.appending(path: "home")] { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    func makeApp(_ name: String, extra: String = "") {
        let contents = foundApps.appending(path: "\(name).app/Contents")
        try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.\(name)</string>\(extra)</dict></plist>"
        try? plist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }
    makeApp("Unused"); makeApp("Resident"); makeApp("Unknown")
    try? fm.createDirectory(at: foundApps.appending(path: "Resident.app/Contents/Library/LoginItems/Helper.app"), withIntermediateDirectories: true)
    let mdls = "#!/bin/bash\napp=\"\"; for a in \"$@\"; do app=\"$a\"; done\ncase \"$app\" in\n  *Unknown.app) echo \"(null)\";;\n  *) [[ \"$2\" == kMDItemLastUsedDate ]] && echo \"2024-01-02 03:04:05 +0000\" || echo \"2020-01-01 00:00:00 +0000\";;\nesac\n"
    try? mdls.write(to: stubs.appending(path: "mdls"), atomically: true, encoding: .utf8)
    try? "#!/bin/bash\necho \"/: Indexing enabled.\"\n".write(to: stubs.appending(path: "mdutil"), atomically: true, encoding: .utf8)
    for stub in ["mdls", "mdutil"] { chmod(stubs.appending(path: stub).path, 0o755) }
    try? "ANALYZERS_APP_DIRS=\"\(foundApps.path)\"\nANALYZERS_LAUNCH_DIRS=\"\(launch.path)\"\n".write(to: tree.appending(path: "config.local.sh"), atomically: true, encoding: .utf8)
    func runFound(_ arguments: [String]) -> (text: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [tree.appending(path: "storage-analyzer/cleanup.sh").path] + arguments
        process.environment = ["HOME": found.appending(path: "home").path, "PATH": "\(stubs.path):/usr/bin:/bin:/usr/sbin:/sbin"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
    let findings = UnusedReview.apps(lines: lines(runFound(["--stale-apps"]).text))
    func row(_ name: String) -> StorageRow? { findings.rows.first { $0.title == name } }
    expect(row("Unused")?.keptReason == nil && row("Unused")?.group != Names.Unused.noRecord, "an unused app is offered: \(String(describing: row("Unused")?.keptReason))")
    expect(row("Resident")?.keptReason?.contains("Runs in the background") == true, "an app that registers a login item is a kept row: \(row("Resident")?.keptReason ?? "offered")")
    expect(row("Unknown")?.keptReason?.contains("no record") == true && row("Unknown")?.group == Names.Unused.noRecord,
           "an app macOS has no record of is kept under its own heading: \(row("Unknown")?.group ?? "none") / \(row("Unknown")?.keptReason ?? "offered")")
    expect(findings.rows.filter { $0.keptReason == nil }.map(\.title) == ["Unused"], "only the unused app can be ticked")
    let refused = runFound(["--stale-apps", "--execute", "--yes"])
    expect(refused.status == 78 && fm.fileExists(atPath: foundApps.appending(path: "Unused.app").path), "found apps with no reviewed list: exit \(refused.status), nothing removed")
    let found_list = root.appending(path: "found-list.txt")
    try? (foundApps.appending(path: "Unused.app").path + "\n").write(to: found_list, atomically: true, encoding: .utf8)
    let applied = runFound(["--stale-apps", "--execute", "--yes", "--only-paths", found_list.path])
    let results = UnusedReview.apps(lines: lines(applied.text), results: true)
    expect(results.rows.map(\.title) == ["Unused"] && results.rows.first?.detail?.hasPrefix(Names.Unused.removed) == true, "the apply is read as a Removed row: \(results.rows.map { "\($0.title): \($0.detail ?? "")" })")
    expect(fm.fileExists(atPath: found.appending(path: "home/.Trash/Unused.app").path) && !fm.fileExists(atPath: foundApps.appending(path: "Unused.app").path), "the removed app is in the Trash")
    expect(fm.fileExists(atPath: foundApps.appending(path: "Resident.app").path), "the kept app is still there")

    // an old-recordings apply goes to the Trash, and is read as Removed rows keyed by the folder's own path
    try? config.write(to: tree.appending(path: "config.local.sh"), atomically: true, encoding: .utf8)   // the recordings folder again
    let recordingList = root.appending(path: "recording-list.txt")
    let oldOne = home.appending(path: "Recordings/Old1").path
    try? (oldOne + "\n").write(to: recordingList, atomically: true, encoding: .utf8)
    let recordingApply = lines(run(["--recordings-older-than", "30", "--execute", "--yes", "--only-paths", recordingList.path]))
    let recordingResults = UnusedReview.recordings(lines: recordingApply, results: true)
    expect(recordingResults.rows.map(\.id) == [oldOne] && recordingResults.rows.first?.detail?.hasPrefix(Names.Unused.removed) == true,
           "a recordings apply is read as one Removed row: \(recordingResults.rows.map { "\($0.id): \($0.detail ?? "")" })")
    expect(fm.fileExists(atPath: home.appending(path: ".Trash/Old1").path) && !fm.fileExists(atPath: oldOne), "the recording is in the Trash")

    print("\(cases) checks, \(failures == 0 ? "the script's output and the screens' rows agree" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
