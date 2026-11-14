import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-recordings-engine` runs the REAL cleanup.sh, recordings mode, under every bash this Mac has
// (the one macOS ships, 3.2, always), in a throwaway HOME it builds, against plain-file fixtures: no real binary, no
// application bundle, nothing of the person's. It checks the rules of the sources: what is one item per layout,
// what is kept, what is refused, that a single folder in ANALYZERS_RECORDINGS_DIR gives today's run, that an apply
// moves only the listed paths into the throwaway Trash with receipts Undo can read, and that the Sources window and
// the engine refuse the same folders. Exit 1 when anything differs; `--execute` only ever runs inside the throwaway home.

@MainActor func probeRecordingsEngine() async -> Never {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    var script: URL?
    for _ in 0..<8 {
        let candidate = dir.appending(path: "storage-analyzer/cleanup.sh")
        if fm.fileExists(atPath: candidate.path) { script = candidate; break }
        dir = dir.deletingLastPathComponent()
    }
    guard let script else { print("FAIL: cleanup.sh was not found above \(CommandLine.arguments[0]), so this probe did not run"); exit(1) }
    let repo = script.deletingLastPathComponent().deletingLastPathComponent()

    var failures = 0, cases = 0
    func check(_ ok: Bool, _ what: @autoclosure () -> String) {
        cases += 1
        if !ok { failures += 1; print("FAIL  \(what())") }
    }

    let root = ProbeScratch.folder("ma-probe-recordings-engine").resolvingSymlinksInPath()
    let tree = root.appending(path: "tree")
    for folder in ["storage-analyzer", "lib"] { try? fm.createDirectory(at: tree.appending(path: folder), withIntermediateDirectories: true) }
    try? fm.copyItem(at: script, to: tree.appending(path: "storage-analyzer/cleanup.sh"))
    if let libs = try? fm.contentsOfDirectory(at: repo.appending(path: "lib"), includingPropertiesForKeys: nil) {
        for lib in libs { try? fm.copyItem(at: lib, to: tree.appending(path: "lib/\(lib.lastPathComponent)")) }
    }
    let home = root.appending(path: "home")

    // plain files and folders only
    func old(_ url: URL, days: Double = 400) { try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -days * 86_400)], ofItemAtPath: url.path) }
    func make(_ path: String, files: [String] = [], days: Double = 400) -> URL {
        let folder = home.appending(path: path)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files {
            let file = folder.appending(path: name)
            try? Data(count: 150_000).write(to: file)
            old(file, days: days)
        }
        old(folder, days: days)
        return folder
    }
    let zoom = "Documents/Zoom"
    let meeting = make("\(zoom)/2025-01-01 10.00.00 Old Meeting", files: ["recording.conf", "video1.mp4", "audio1.m4a"])
    let pair = make("\(zoom)/2025-01-02 10.00.00 Pair Only", files: ["video2.mp4", "audio2.m4a"])
    let unconverted = make("\(zoom)/2025-01-03 10.00.00 Not Converted", files: ["double_click_to_convert_01.zoom"])
    let stranger = make("\(zoom)/Family Photos", files: ["notes.txt", "a.jpg"])
    let recent = make("\(zoom)/2026-11-12 10.00.00 This Week", files: ["recording.conf", "video3.mp4", "audio3.m4a"], days: 1)
    _ = make(zoom)
    let looseOld = home.appending(path: "\(zoom)/loose.mp4"), looseNote = home.appending(path: "\(zoom)/loose.txt"), looseNew = home.appending(path: "\(zoom)/new.mp4")
    for file in [looseOld, looseNote, looseNew] { try? Data(count: 120_000).write(to: file) }
    old(looseOld); old(looseNote); old(looseNew, days: 2)
    old(home.appending(path: zoom), days: 1)
    let shots = make("Desktop/Shots", files: ["old.mov", "old.png", "old.MP4"])
    try? Data(count: 100_000).write(to: shots.appending(path: "new.mov")); old(shots.appending(path: "new.mov"), days: 3)
    let audio1 = make("Notes/audio/OldA", files: ["a.m4a"]), audio2 = make("Notes/audio/OldB", files: ["b.m4a"])
    _ = make("Notes/audio/NewC", files: ["c.m4a"], days: 2)
    _ = make("Notes/audio", days: 1)
    let whisper = make("superwhisper/recordings/1700000000", files: ["meta.json", "output.wav"])
    _ = make("superwhisper/recordings", days: 1)
    let cloud = make("Library/CloudStorage/OneDrive-Test/Recordings/Old", files: ["x.mp4"])
    let gdrive = make("Library/CloudStorage/GDrive-Test/Zoom/2025-01-01 10.00.00 In The Cloud", files: ["recording.conf", "video9.mp4", "audio9.m4a"])
    try? fm.createSymbolicLink(at: home.appending(path: "link"), withDestinationURL: home.appending(path: "Library/CloudStorage/GDrive-Test"))
    let linkTarget = make("Notes/target/Old", files: ["t.m4a"])
    try? fm.createSymbolicLink(at: home.appending(path: "Notes/linked"), withDestinationURL: home.appending(path: "Notes/target"))
    _ = make("Notes/target", days: 1)

    func config(_ text: String) { try? text.write(to: tree.appending(path: "config.local.sh"), atomically: true, encoding: .utf8) }
    func sources(_ entries: [String]) -> String { "ANALYZERS_RECORDING_SOURCES=( \(entries.map { "\"\($0)\"" }.joined(separator: " ")) )\n" }
    func run(_ shell: String, _ arguments: [String], extra: [String: String] = [:]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [tree.appending(path: "storage-analyzer/cleanup.sh").path] + arguments
        var environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for (key, value) in extra { environment[key] = value }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
    func lines(_ text: String) -> [String] { text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    func listed(_ rows: StorageRows, _ source: String) -> Set<String> { Set(rows.rows(inTab: source).filter(\.isChoosable).map(\.id)) }

    var shells = ["/bin/bash"]
    for extra in ["/opt/homebrew/bin/bash", "/usr/local/bin/bash"] where fm.isExecutableFile(atPath: extra) { shells.append(extra) }
    let all = [sources(["zoom|on|\(home.path)/\(zoom)", "screenRecordings|on|\(shots.path)", "superwhisper|off|\(home.path)/superwhisper/recordings",
                        "custom|on|\(home.path)/Notes/audio", "custom|on|\(cloud.deletingLastPathComponent().path)"]).replacingOccurrences(of: "\n", with: "\n")][0]
    config(all)

    for shell in shells {
        let tag = shell == "/bin/bash" ? "/bin/bash" : "bash"
        let out = lines(run(shell, ["--recordings-older-than", "30"], extra: shell == "/bin/bash" ? ["ANALYZERS_BASH_CANDIDATES": "/nonexistent"] : [:]))
        let rows = UnusedReview.recordings(lines: out)
        check(out.contains { $0.hasPrefix("cleanup | recordings | DRY RUN | ") }, "\(tag): the run has its banner")
        let zoomIDs = listed(rows, "zoom")
        check(zoomIDs == [meeting.path, pair.path, looseOld.path], "\(tag): Zoom lists the old meeting folders with its signature and the old loose .mp4, got \(zoomIDs.map { ($0 as NSString).lastPathComponent }.sorted())")
        let keptZoom = rows.rows(inTab: "zoom").filter { !$0.isChoosable }
        check(keptZoom.count == 1 && keptZoom[0].id == unconverted.path && keptZoom[0].keptReason?.contains("Zoom has not converted") == true,
              "\(tag): a Zoom folder holding a .zoom file is kept, with its reason: \(keptZoom.map { "\($0.id): \($0.keptReason ?? "")" })")
        let allIDs = Set(rows.rows.map(\.id))
        check(!allIDs.contains(stranger.path) && !allIDs.contains(recent.path) && !allIDs.contains(looseNew.path) && !allIDs.contains(looseNote.path),
              "\(tag): a folder without Zoom's signature, a recent meeting, a recent file and a .txt are not listed")
        check(listed(rows, "screenRecordings") == [shots.appending(path: "old.mov").path, shots.appending(path: "old.MP4").path],
              "\(tag): Screen Recordings lists the old .mov and .mp4 files only, never a .png or a recent file: \(listed(rows, "screenRecordings").map { ($0 as NSString).lastPathComponent }.sorted())")
        check(listed(rows, "custom:\(home.path)/Notes/audio") == [audio1.path, audio2.path], "\(tag): a custom source lists its old subfolders, as today (NewC is recent)")
        check(rows.rows(inTab: "superwhisper").isEmpty && out.contains("Turned off in Sources") && !allIDs.contains(whisper.path),
              "\(tag): a source that is off lists nothing and says it is turned off")
        check(!allIDs.contains(cloud.path) && out.contains { $0.contains("not used:") && $0.contains("Library folder") },
              "\(tag): a source under Library/CloudStorage is refused with its reason, and nothing in it is listed")
        check(rows.notes.contains { $0.contains("OneDrive-Test") || $0.contains("syncs to the cloud") }, "\(tag): the screen says a folder was not used: \(rows.notes)")
    }

    // refusals: the engine and the Sources window refuse the same folders
    let homeBase = home.path
    let refusalCases: [(path: String, layout: String, definition: RecordingSourceDefinition.Layout)] = [
        (homeBase, "custom", .folders), ("/", "custom", .folders), ("\(homeBase)/Documents", "custom", .folders), ("\(homeBase)/Desktop", "custom", .folders),
        ("\(homeBase)/Movies", "custom", .folders), ("\(homeBase)/Library", "custom", .folders), ("\(homeBase)/Library/CloudStorage/OneDrive-X", "custom", .folders),
        ("\(homeBase)/Library/Mobile Documents/com~apple~CloudDocs", "custom", .folders), ("\(homeBase)/Library/Containers/com.x", "custom", .folders),
        ("\(homeBase)/Library/Group Containers/group.x", "custom", .folders), ("/Volumes/Disk", "custom", .folders), ("\(homeBase)/Notes/linked", "custom", .folders),
        ("\(homeBase)/Documents/Zoom", "custom", .folders), ("\(homeBase)/Notes/audio", "custom", .folders), ("/Volumes/Disk/Recordings", "custom", .folders),
        ("\(homeBase)/Desktop", "screenRecordings", .files), ("\(homeBase)/Notes/../Documents", "custom", .folders),
        // a link in the middle of the path into a cloud mount (the review's repro), and what lies outside the home folder
        ("\(homeBase)/link/Zoom", "zoom", .meetingFolders), ("\(homeBase)/link", "custom", .folders),
        ("\(homeBase)/Library/Application Support", "custom", .folders), ("\(homeBase)/Library/Application Support/Zoom", "custom", .folders),
        ("/Applications", "custom", .folders), ("/Library", "custom", .folders), ("/Users", "custom", .folders), ("/System/Volumes/Data", "custom", .folders),
        ("/private/tmp", "custom", .folders), ("\(homeBase)/.ssh", "custom", .folders), ("\(homeBase)/.config/recordings", "custom", .folders),
        ("\(homeBase)/Movies/Loom/Temporary", "loomTemporary", .folders), ("\(homeBase)/Music/Podcasts", "custom", .folders),
    ]
    for entry in refusalCases {
        config(sources(["\(entry.layout)|on|\(entry.path)"]))
        let output = run("/bin/bash", ["--recordings-older-than", "30"])
        let engineRefuses = output.contains("not used:")
        var isLink = false
        if let target = try? fm.destinationOfSymbolicLink(atPath: entry.path), !target.isEmpty { isLink = true }
        // where it really leads: the same question the app's readers answer
        let resolved = fm.fileExists(atPath: entry.path) ? URL(fileURLWithPath: entry.path).resolvingSymlinksInPath().path : nil
        let windowRefuses = RecordingFolderRule.refusal(entry.path, layout: entry.definition, home: homeBase, homeResolved: homeBase,
                                                        isLink: isLink, resolved: resolved) != nil
        check(engineRefuses == windowRefuses, "\(entry.path) (\(entry.layout)): the engine \(engineRefuses ? "refuses" : "uses") it and the Sources window \(windowRefuses ? "refuses" : "allows") it")
    }
    check(run("/bin/bash", ["--recordings-older-than", "30"]).isEmpty == false, "the engine ran")
    // Screen Recordings (files layout) may be the whole Desktop, Movies or a screencapture folder: only a folder-per-recording
    // source is refused for a standard folder, and the engine lists the old .mov there and nothing else
    for place in ["Desktop", "Movies"] {
        let folder = make(place, files: ["rec-old.mov", "pic.png"])
        try? Data(count: 90_000).write(to: folder.appending(path: "rec-new.mov")); old(folder.appending(path: "rec-new.mov"), days: 1)
        config(sources(["screenRecordings|on|\(homeBase)/\(place)"]))
        let output = lines(run("/bin/bash", ["--recordings-older-than", "30"]))
        let rowsHere = UnusedReview.recordings(lines: output)
        check(!output.contains { $0.contains("not used:") } && Set(rowsHere.rows.map(\.id)) == [folder.appending(path: "rec-old.mov").path],
              "Screen Recordings on the whole \(place) folder is allowed and lists only the old .mov: \(output.filter { $0.hasPrefix("[") || $0.contains("not used") })")
        check(RecordingFolderRule.refusal("\(homeBase)/\(place)", layout: .files, home: homeBase) == nil
              && RecordingFolderRule.refusal("\(homeBase)/\(place)", layout: .folders, home: homeBase) != nil,
              "\(place): the Sources window allows it for files and refuses it for folders")
    }
    // the review's repro: a link in the middle of a path into a cloud mount. It lists nothing and --execute removes nothing.
    config(sources(["zoom|on|\(homeBase)/link/Zoom"]))
    let throughLink = lines(run("/bin/bash", ["--recordings-older-than", "30", "--execute", "--yes"]))
    check(throughLink.contains { $0.contains("not used:") && $0.contains("leads through a link") } && fm.fileExists(atPath: gdrive.path)
          && !throughLink.contains { $0.hasPrefix("[TRASHED]") || $0.hasPrefix("[DRY]") }, "a source reached through a link into CloudStorage fails closed and nothing in it moves: \(throughLink.filter { $0.contains("not used") || $0.hasPrefix("[") })")
    check(fm.fileExists(atPath: gdrive.path), "the cloud copy is still there")
    // a link is never followed: the target's folder is not listed through it
    config(sources(["custom|on|\(homeBase)/Notes/linked"]))
    check(!lines(run("/bin/bash", ["--recordings-older-than", "30"])).contains { $0.contains(linkTarget.path) || $0.contains("linked/Old") }, "a symlinked source lists nothing from its target")

    // ANALYZERS_RECORDINGS_DIR alone: today's run, line for line, in every shell
    for shell in shells {
        config("ANALYZERS_RECORDINGS_DIR=\"\(homeBase)/Notes/audio\"\n")
        let out = lines(run(shell, ["--recordings-older-than", "30"]))
        let body = out.drop { !$0.hasPrefix("### Recordings older than 30 days") }.prefix { !$0.hasPrefix("=====") }
        let items = body.dropFirst()
        let legacyRows = UnusedReview.recordings(lines: Array(items))
        check(!out.contains { $0.hasPrefix("### Source") } && Set(legacyRows.rows.map(\.id)) == [audio1.path, audio2.path],
              "\(shell): ANALYZERS_RECORDINGS_DIR alone prints no source heading and lists exactly its old folders: \(Array(items))")
        check(items.allSatisfy { $0.hasPrefix("[DRY]") } && items.count == 2, "\(shell): and nothing else but those lines: \(Array(items))")
    }
    config("")
    check(lines(run("/bin/bash", ["--recordings-older-than", "30"])).contains("(ANALYZERS_RECORDINGS_DIR not set — skipping)"), "with nothing configured, today's skip line")
    config("ANALYZERS_RECORDING_SOURCES=( )\nANALYZERS_RECORDINGS_DIR=\"\(homeBase)/Notes/audio\"\n")
    for shell in shells {
        let emptyList = lines(run(shell, ["--recordings-older-than", "30", "--execute", "--yes"]))
        check(UnusedReview.recordings(lines: emptyList).rows.isEmpty && emptyList.contains { $0.contains("no recording folder is turned on in Sources") } && fm.fileExists(atPath: audio1.path),
              "\(shell): a list that exists but is empty means NONE: the old ANALYZERS_RECORDINGS_DIR line is not read, and nothing moves")
    }
    try? fm.moveItem(at: tree.appending(path: "lib/recording-sources.tsv"), to: root.appending(path: "tsv-away"))
    config(sources(["custom|on|\(homeBase)/Notes/audio"]))
    let withoutList = run("/bin/bash", ["--recordings-older-than", "30", "--execute", "--yes"])
    check(withoutList.contains("recording-sources.tsv is missing") && fm.fileExists(atPath: audio1.path), "a list of sources with no recording-sources.tsv stops (fails closed) and removes nothing")
    try? fm.moveItem(at: root.appending(path: "tsv-away"), to: tree.appending(path: "lib/recording-sources.tsv"))

    // an apply: only listed paths move, into the throwaway Trash, with receipts Undo reads
    config(all)
    let list = root.appending(path: "list.txt")
    try? (meeting.path + "\n" + shots.appending(path: "old.mov").path + "\n" + audio1.path + "\n" + unconverted.path + "\n").write(to: list, atomically: true, encoding: .utf8)
    let applied = lines(run("/bin/bash", ["--recordings-older-than", "30", "--execute", "--yes", "--only-paths", list.path]))
    let trash = home.appending(path: ".Trash")
    check(!fm.fileExists(atPath: meeting.path) && fm.fileExists(atPath: trash.appending(path: meeting.lastPathComponent).path), "a listed Zoom meeting is in the Trash")
    check(!fm.fileExists(atPath: shots.appending(path: "old.mov").path) && !fm.fileExists(atPath: audio1.path), "a listed file and a listed custom folder are in the Trash")
    check(fm.fileExists(atPath: pair.path) && fm.fileExists(atPath: audio2.path) && fm.fileExists(atPath: shots.appending(path: "old.MP4").path)
          && fm.fileExists(atPath: looseOld.path) && fm.fileExists(atPath: cloud.path) && fm.fileExists(atPath: whisper.path), "nothing outside the list moved")
    check(fm.fileExists(atPath: unconverted.path) && applied.contains { $0.hasPrefix("[KEEP]") && $0.contains("Zoom has not converted") },
          "an unconverted Zoom folder stays even when it is on the list")
    let results = UnusedReview.recordings(lines: applied, results: true)
    check(Set(results.rows.map(\.id)) == [meeting.path, shots.appending(path: "old.mov").path, audio1.path], "the apply is read as one Removed row per moved path: \(results.rows.map(\.id))")
    let log = home.appending(path: "mac-analyzers/reports/storage/cleanup-recordings.log")
    let undoable = UndoLedger.trashedItems(in: log, source: "Old Recordings", trash: trash)
    check(undoable.count == 3 && undoable.allSatisfy { $0.restorability == .restorable && $0.identity != nil }, "Undo reads each receipt as restorable: \(undoable.map { $0.restorability })")
    if let item = undoable.first(where: { $0.originalPath == meeting.path }) {
        _ = try? UndoLedger.restore(item, trash: trash)
        check(fm.fileExists(atPath: meeting.path), "restoring a Zoom meeting from Undo brings the folder back")
    } else { check(false, "the Zoom meeting's receipt was not found") }

    print(failures == 0 ? "PASS  \(cases) checks hold, under \(shells.joined(separator: " and "))" : "\(failures) of \(cases) checks FAILED")
    ProbeScratch.finish(failures == 0 ? 0 : 1)
}
