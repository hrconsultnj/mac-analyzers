import Foundation
import Synchronization
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-recording-sources` judges itself (exit 1 when a rule breaks): discovery on stand-in readers, the list
// both sides read, and the config round trip. It runs in a throwaway home (`ProbeSandbox`) and never reads a folder of the
// person's: every path discovery asks about is recorded, and asking about Documents, Desktop, Downloads or another app's
// container before the person has clicked fails the probe.

@MainActor func probeRecordingSources() async -> Never {
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : ": " + detail))
        if !ok { failures += 1 }
    }
    let home = AnalyzersPaths.home.path
    let list = ProbeSandbox.sourceRoot.appending(path: "lib/recording-sources.tsv")
    RecordingSourceCatalog.useList(at: list)
    let catalog = RecordingSourceCatalog.definitions
    check("the list is found and names every source", catalog.count >= 11, "\(catalog.count) sources from \(list.path)")

    // 1. the app and the engine read the list the same way: awk, as cleanup.sh does, against the Swift reader
    func awk(_ field: Int, _ id: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        process.arguments = ["-F", "\t", "-v", "id=\(id)", "-v", "f=\(field)", "/^#/ {next} $1 == id {print $f; exit}", list.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try? process.run(); process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .newlines)
    }
    var disagree: [String] = []
    for definition in catalog {
        let layout = awk(4, definition.id), exts = awk(5, definition.id), keep = awk(6, definition.id), offer = awk(7, definition.id)
        if layout != definition.layout.rawValue { disagree.append("\(definition.id) layout \(layout) / \(definition.layout.rawValue)") }
        if (exts == "-" ? "" : exts) != definition.extensions.joined(separator: ",") { disagree.append("\(definition.id) extensions") }
        if (keep == "zoomFile") != definition.keepIfZoomFile { disagree.append("\(definition.id) keepIf") }
        let swiftOffer: String
        switch definition.offer { case .on: swiftOffer = "on"; case .offWithWarning: swiftOffer = "offWithWarning"; case .notOffered: swiftOffer = "notOffered" }
        if offer != swiftOffer { disagree.append("\(definition.id) offer") }
        if awk(2, definition.id) != definition.title { disagree.append("\(definition.id) title") }
        if Names.Recordings.sourceTitles[definition.id] != definition.title { disagree.append("\(definition.id) title is not in the name table") }
    }
    check("awk and Swift read every line of the list alike, and the titles are in the name table", disagree.isEmpty, disagree.joined(separator: "; "))
    check("only the person's own folders are custom, and they are read like today's folder (one level down)",
          catalog.first { $0.id == "custom" }?.layout == .folders && catalog.filter { $0.id == "custom" }.count == 1)

    // 2. discovery on stand-in readers, recording every path it is asked about
    let touched = Mutex<[String]>([])
    func readers(defaults: [String: String] = [:], existing: Set<String> = [], apps: Set<String> = [], mounts: [String] = []) -> RecordingReaders {
        RecordingReaders(home: home,
                         defaultsString: { domain, key in defaults["\(domain)/\(key)"] },
                         folderExists: { path in touched.withLock { $0.append(path) }; return existing.contains(path) },
                         appInstalled: { apps.contains($0) }, cloudMountNames: { mounts })
    }
    func find(_ id: String, _ sources: [RecordingSource]) -> RecordingSource? { sources.first { $0.id == id } }
    let guardedPrefixes = ["\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads", "\(home)/Library/Containers", "\(home)/Library/Group Containers"]
    func guarded() -> [String] { touched.withLock { $0 }.filter { path in guardedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") } } }

    // SuperWhisper: from its own setting
    touched.withLock { $0 = [] }
    let whisper = "\(home)/superwhisper/recordings"
    var found = RecordingDiscovery.discover(readers: readers(defaults: ["com.superduper.superwhisper/appFolderDirectory": home], existing: [whisper], apps: ["superwhisper"]), saved: [])
    check("SuperWhisper is found from its own setting, readable, offered OFF with its warning",
          find("superwhisper", found)?.path == whisper && find("superwhisper", found)?.access == .readable
          && find("superwhisper", found)?.enabled == false && find("superwhisper", found)?.offer == .offWithWarning
          && find("superwhisper", found)?.warning?.contains("Keep Recordings For") == true, "\(String(describing: find("superwhisper", found)))")
    // ... and a saved choice keeps its switch
    found = RecordingDiscovery.discover(readers: readers(defaults: ["com.superduper.superwhisper/appFolderDirectory": home], existing: [whisper]),
                                        saved: [RecordingSourceEntry(id: "superwhisper", enabled: true, path: whisper)])
    check("a migrated SuperWhisper folder stays on", find("superwhisper", found)?.enabled == true)

    // Screen recordings: location-screenrecording, then location, then the Desktop
    let shots = "\(home)/Pictures/Shots", clips = "\(home)/Movies/Clips"
    var sr = RecordingDiscovery.discover(readers: readers(defaults: ["com.apple.screencapture/location-screenrecording": "~/Movies/Clips", "com.apple.screencapture/location": "~/Pictures/Shots"], existing: [shots, clips]), saved: [])
    check("Screen Recordings reads location-screenrecording first", find("screenRecordings", sr)?.path == clips && find("screenRecordings", sr)?.access == .readable)
    sr = RecordingDiscovery.discover(readers: readers(defaults: ["com.apple.screencapture/location": "~/Pictures/Shots"], existing: [shots]), saved: [])
    check("Screen Recordings falls back to location", find("screenRecordings", sr)?.path == shots)
    touched.withLock { $0 = [] }
    sr = RecordingDiscovery.discover(readers: readers(), saved: [])
    check("with neither setting it is the Desktop, shown as Needs Access, and the Desktop was not looked at",
          find("screenRecordings", sr)?.path == "\(home)/Desktop" && find("screenRecordings", sr)?.access == .needsAccess("Desktop") && guarded().isEmpty,
          "touched: \(touched.withLock { $0 })")
    touched.withLock { $0 = [] }
    sr = RecordingDiscovery.discover(readers: readers(defaults: ["com.apple.screencapture/location-screenrecording": "~/Desktop/Screenshots/2026/11", "com.apple.screencapture/location": "~/Pictures/Shots"], existing: [shots]), saved: [])
    check("a recordings folder in a guarded place is NOT replaced by the next setting, and is not looked at",
          find("screenRecordings", sr)?.access == .needsAccess("Desktop") && find("screenRecordings", sr)?.path == "\(home)/Desktop/Screenshots/2026/11" && guarded().isEmpty)

    // Zoom: shown as Needs Access without reading Documents; absent when Zoom is not installed
    touched.withLock { $0 = [] }
    found = RecordingDiscovery.discover(readers: readers(existing: ["\(home)/Documents/Zoom"], apps: ["zoom.us"]), saved: [])
    check("Zoom is Needs Access, offered on, and Documents was never read",
          find("zoom", found)?.access == .needsAccess("Documents") && find("zoom", found)?.offer == .on && find("zoom", found)?.path == "\(home)/Documents/Zoom" && guarded().isEmpty,
          "touched: \(touched.withLock { $0 })")
    check("Zoom is not listed on a Mac without Zoom", find("zoom", RecordingDiscovery.discover(readers: readers(), saved: [])) == nil)
    found = RecordingDiscovery.discover(readers: readers(existing: ["\(home)/Documents/Zoom"], apps: ["zoom.us"]), saved: [], allowed: ["Documents"])
    check("after the person clicks Look in Documents, Zoom's folder is read", find("zoom", found)?.access == .readable)

    // not offered, with reasons, from the app's presence or a mount's name alone
    touched.withLock { $0 = [] }
    found = RecordingDiscovery.discover(readers: readers(apps: ["MacWhisper", "Granola"], mounts: ["OneDrive-Personal"]), saved: [])
    check("Voice Memos, a cloud mount and MacWhisper are not offered, each with its reason, and nothing was opened",
          ["voiceMemos", "cloudMeetings", "macwhisper", "granola"].allSatisfy { find($0, found)?.offer == .notOffered && find($0, found)?.warning?.isEmpty == false }
          && find("rewind", found) == nil && find("wisprFlow", found) == nil
          && !touched.withLock { $0 }.contains { $0.contains("CloudStorage") || $0.contains("Containers") },
          "touched: \(touched.withLock { $0 })")
    check("nothing that is not offered is ever written to the config",
          RecordingSourcesStore.entries(from: found).allSatisfy { !["voiceMemos", "cloudMeetings", "macwhisper", "granola"].contains($0.id) })

    // preference-derived paths on an external disk or in iCloud Drive are guarded places too: not looked at before a click
    touched.withLock { $0 = [] }
    let disk = RecordingDiscovery.discover(readers: readers(defaults: ["com.apple.screencapture/location-screenrecording": "/Volumes/Disk/Rec"], existing: ["/Volumes/Disk/Rec"]), saved: [])
    check("a recordings folder on an external disk is Needs Access (External Disks) and was not looked at",
          find("screenRecordings", disk)?.access == .needsAccess("External Disks") && !touched.withLock { $0 }.contains { $0.hasPrefix("/Volumes") })
    check("iCloud Drive and /Volumes are guarded places, the Library is not",
          RecordingDiscovery.protectedArea("\(home)/Library/Mobile Documents/com~apple~CloudDocs/x", home: home) == "iCloud Drive"
          && RecordingDiscovery.protectedArea("/Volumes/Disk", home: home) == "External Disks"
          && RecordingDiscovery.protectedArea("\(home)/documents/Zoom", home: home) == "Documents"
          && RecordingDiscovery.protectedArea("\(home)/DESKTOP", home: home) == "Desktop"
          && RecordingDiscovery.protectedArea("\(home)/library/mobile documents/x", home: home) == "iCloud Drive"
          && RecordingDiscovery.protectedArea("/volumes/Disk", home: home) == "External Disks"
          && RecordingDiscovery.protectedArea("\(home)/Documentſ/Zoom", home: home) == "Documents"
          && RecordingDiscovery.protectedArea("\(home)/DeſkTop/x", home: home) == "Desktop"
          && RecordingDiscovery.protectedArea("\(home)/Des\u{212A}top", home: home) == "Desktop"
          && RecordingDiscovery.protectedArea("\(home)/Downloadſ", home: home) == "Downloads"
          && RecordingDiscovery.protectedArea("\(home)/Library/Application Support", home: home) == nil)
    // a discovered folder that leads, through a link, somewhere that can never be a source is refused, shown as such, and never written
    let linked = RecordingReaders(home: home, defaultsString: { domain, key in ["com.apple.screencapture/location-screenrecording": "~/Pictures/Shots"]["\(domain)/\(key)"] },
                                  folderExists: { $0 == shots }, appInstalled: { _ in false }, cloudMountNames: { [] },
                                  linkInfo: { path in path == shots ? (false, "\(home)/Library/CloudStorage/GDrive-Test/Shots") : nil })
    let viaLink = RecordingDiscovery.discover(readers: linked, saved: [])
    if case .refused(let why)? = find("screenRecordings", viaLink)?.access { check("a discovered folder that leads into CloudStorage is refused with its reason", why.contains("leads through a link")) }
    else { check("a discovered folder that leads into CloudStorage is refused with its reason", false, "\(String(describing: find("screenRecordings", viaLink)?.access))") }
    check("a refused folder is never written to the config", !RecordingSourcesStore.entries(from: viaLink).contains { $0.id == "screenRecordings" })
    func manual(_ kind: String, _ path: String, access: RecordingSource.Access = .readable) -> RecordingSource {
        RecordingSource(id: kind == "custom" ? "custom:\(path)" : kind, kind: kind, title: kind, symbol: "folder", path: path, offer: .on, access: access, warning: nil, enabled: true)
    }
    let written = RecordingSourcesStore.entries(from: [manual("custom", "\(home)/Notes/audio"), manual("zoom", "\(home)/Documents/Zoom"), manual("bogus", "\(home)/Notes/x"),
                                                       manual("custom", "\(home)/Notes/a\tb"), manual("custom", "\(home)/Notes/a\nb"), manual("custom", "/Applications"),
                                                       manual("custom", "\(home)/Library/Application Support/X"), manual("custom", "/etc"), manual("custom", "\(home)/.ssh")])
    check("only a source of the list or a custom folder that can be one is written: not an unknown id, a tab or line break, or a place outside the home",
          written.map(\.path) == ["\(home)/Notes/audio", "\(home)/Documents/Zoom"], "\(written.map(\.path))")

    // no protected place was read in any of the above, and no container
    check("discovery never read Documents, Desktop, Downloads or a container before a click", guarded().isEmpty, "\(guarded())")

    // 3. migration of today's single folder, and what the window adds
    let base = RecordingDiscovery.discover(readers: readers(defaults: ["com.superduper.superwhisper/appFolderDirectory": home], existing: [whisper]), saved: [])
    let migratedWhisper = RecordingSourcesStore.migrating(folder: whisper + "/", into: base, readers: readers(), allowed: [])
    check("the owner's folder that is SuperWhisper's becomes that source, ON", find("superwhisper", migratedWhisper)?.enabled == true && migratedWhisper.count == base.count)
    let migratedOther = RecordingSourcesStore.migrating(folder: "\(home)/Notes/audio", into: base, readers: readers(), allowed: [])
    check("any other folder becomes the first custom source, ON, named for the folder",
          migratedOther.last?.isCustom == true && migratedOther.last?.enabled == true && migratedOther.last?.title == "audio")
    switch RecordingSourcesStore.adding(folder: whisper, to: base, readers: readers(), isLink: false, allowed: []) {
    case .alreadyListed(let list, let title): check("a folder a source already covers becomes that source", title == "SuperWhisper" && find("superwhisper", list)?.enabled == true && list.count == base.count)
    default: check("a folder a source already covers becomes that source", false)
    }
    var refusedAll = true
    for (path, isLink) in [(home, false), ("/", false), ("\(home)/Documents", false), ("\(home)/Library/CloudStorage/OneDrive-X/Recordings", false),
                           ("\(home)/Library/Containers/com.x/Data", false), ("\(home)/Notes", true), ("relative/path", false),
                           ("\(home)/Library/Application Support", false), ("/Applications", false), ("/Library", false), ("/Users", false),
                           ("\(home)/.ssh", false), ("/Volumes/Disk", false), ("/etc/x", false),
                           ("\(home)/library/cloudstorage/x", false), ("\(home)/LIBRARY/CLOUDSTORAGE/x", false), ("\(home)/Library/CONTAINERS/c", false),
                           ("\(home)/library/group containers/g", false), ("\(home)/library/MOBILE DOCUMENTS/x", false), ("\(home)/DOCUMENTS", false),
                           ("\(home)/.SSH", false), ("/VOLUMES/Disk", false), ("\(home.uppercased())/Library/CloudStorage/x", false),
                           ("\(home)/Movieſ", false), ("\(home)/Documentſ", false), ("\(home)/Des\u{212A}top", false), ("\(home)/Library/Suppoſt", false)] {
        if case .refused = RecordingSourcesStore.adding(folder: path, to: base, readers: readers(), isLink: isLink, allowed: []) {} else { refusedAll = false; print("      not refused: \(path)") }
    }
    check("the window refuses the folders the engine refuses", refusedAll)
    check("a folder inside Documents is allowed, and the whole Desktop is allowed only for files",
          RecordingFolderRule.refusal("\(home)/Documents/Zoom", home: home, isLink: false) == nil
          && RecordingFolderRule.refusal("\(home)/Desktop", home: home, isLink: false) != nil
          && RecordingFolderRule.refusal("\(home)/Desktop", layout: .files, home: home, isLink: false) == nil
          && RecordingFolderRule.refusal("\(home)/DESKTOP", layout: .files, home: home, isLink: false) == nil
          && RecordingFolderRule.refusal("\(home)/documents/Zoom", home: home, isLink: false) == nil
          && RecordingFolderRule.refusal("/volumes/Disk/Rec", home: home, isLink: false) == nil)
    check("the summary for Setup reads 'on' and 'needs access'", RecordingSourcesStore.summary(find("zoom", RecordingDiscovery.discover(readers: readers(apps: ["zoom.us"]), saved: [])).map { [$0] } ?? []) == "1 on · 1 needs access")

    // 4. the config round trip: what the app writes is what ConfigStore reads and what bash splits
    let nasty = ["\(home)/Notes #1/a b", "/Volumes/X/it's \"quoted\" $dollar `tick` back\\slash", "/tmp/pipe|name", "\(home)/superwhisper/recordings"]
    let entries = [RecordingSourceEntry(id: "zoom", enabled: true, path: "\(home)/Documents/Zoom"),
                   RecordingSourceEntry(id: "custom", enabled: true, path: nasty[0]),
                   RecordingSourceEntry(id: "custom", enabled: false, path: nasty[1]),
                   RecordingSourceEntry(id: "custom", enabled: true, path: nasty[2]),
                   RecordingSourceEntry(id: "superwhisper", enabled: true, path: nasty[3])]
    try? FileManager.default.createDirectory(at: AnalyzersPaths.configLocal.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "# my own line\nANALYZERS_RECORDINGS_DIR=\"$HOME/Old\"\n".write(to: AnalyzersPaths.configLocal, atomically: true, encoding: .utf8)
    let config = ConfigStore()
    check("a config with only ANALYZERS_RECORDINGS_DIR reads as no list of sources and the folder", config.storage.recordingSources.isEmpty && config.storage.recordingsDir == "\(home)/Old")
    let starting = RecordingSourcesStore.startingSources(config: config, readers: readers())
    check("and the Sources window starts with that folder migrated in, on", starting.contains { $0.isCustom && $0.path == "\(home)/Old" && $0.enabled })
    config.storage.recordingSources = entries
    config.storage.recordingsDays = 180
    try? config.save()
    check("ANALYZERS_RECORDINGS_DIR from the person's own line is not copied into the managed block once the list is written",
          (try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8))?.components(separatedBy: "ANALYZERS_RECORDINGS_DIR").count == 2)
    let reloaded = ConfigStore()
    check("the sources and the days come back exactly, paths with # \" ' $ ` \\ | and spaces included",
          reloaded.storage.recordingSources == entries && reloaded.storage.recordingsDays == 180,
          "\(reloaded.storage.recordingSources.map(\.path))")
    let text = (try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8)) ?? ""
    check("the managed block holds the list, and the single folder is no longer written twice (the person's own line stays)",
          text.contains("ANALYZERS_RECORDING_SOURCES=(") && text.contains("ANALYZERS_RECORDINGS_DAYS=180") && text.contains("# my own line")
          && text.components(separatedBy: "ANALYZERS_RECORDINGS_DIR").count == 2)
    // removing every source and saving must never bring the old single folder back
    let cleared = ConfigStore()
    try? RecordingSourcesStore.save([], days: 90, in: cleared)
    let afterClear = ConfigStore()
    check("a saved empty list is remembered as a list (so the old folder is never read again) and the folder is cleared",
          afterClear.storage.recordingSources.isEmpty && afterClear.storage.recordingSourcesConfigured && cleared.storage.recordingsDir.isEmpty
          && ((try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8)) ?? "").contains("ANALYZERS_RECORDING_SOURCES=( )"))
    check("and the Sources window does not migrate the old folder in again",
          !RecordingSourcesStore.startingSources(config: afterClear, readers: readers()).contains { $0.isCustom && $0.path == "\(home)/Old" })
    try? FileManager.default.removeItem(at: AnalyzersPaths.configLocal)
    try? "".write(to: AnalyzersPaths.configLocal, atomically: true, encoding: .utf8)
    let again = ConfigStore(); again.storage.recordingSources = entries; again.storage.recordingsDays = 180; try? again.save()
    for shell in ["/bin/bash"] + ["/opt/homebrew/bin/bash", "/usr/local/bin/bash"].filter({ FileManager.default.isExecutableFile(atPath: $0) }) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", "source \"$1\"; for e in \"${ANALYZERS_RECORDING_SOURCES[@]}\"; do id=${e%%|*}; rest=${e#*|}; state=${rest%%|*}; path=${rest#*|}; printf '%s\\t%s\\t%s\\n' \"$id\" \"$state\" \"$path\"; done", "bash", AnalyzersPaths.configLocal.path]
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe(); process.standardOutput = pipe
        try? process.run(); process.waitUntilExit()
        let rows = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let expected = entries.map { "\($0.id)\t\($0.enabled ? "on" : "off")\t\($0.path)" }
        check("\(shell) splits every element of the list into the same id, state and path", rows == expected, "\(rows)")
    }
    print(failures == 0 ? "PASS  every check holds" : "\(failures) checks FAILED")
    ProbeScratch.finish(failures == 0 ? 0 : 1)
}
