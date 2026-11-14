import Foundation

/// Example runs for looking at the Storage screens headless. Written as the engines print them
/// and read by the same builders as a real run, so a fixture can never show a shape the
/// screens do not get. Only `SnapshotRunner` reaches these (through `StorageGroup.fixtureTargets`).
public enum StorageFixtures {

    private static var home: String { NSHomeDirectory() }

    public static func caches() -> StorageRows {
        let lines = """
        roots=\(home)/Projects  cache>3d  nm>14d(any)  turbo<=2GB  snap-keep=5d
        ### 1. Build caches not written in >3 days (regenerable)
        [DRY]      2.0 GB  \(home)/Projects/web-app/apps/mobile/.next
        [DRY]    620.0 MB  \(home)/Projects/web-app/.next
        [DRY]     96.0 MB  \(home)/Projects/web-app/dist
        [DRY]    410.0 MB  \(home)/Projects/api/.turbo
        [DRY]        0 KB  \(home)/Projects/api/build
        ### 2. node_modules of repos idle >14d
        [DRY]      1.8 GB  \(home)/Projects/web-app/node_modules
        [DRY]      1.1 GB  \(home)/Projects/web-app/apps/mobile/node_modules
        [DRY]    900.0 MB  \(home)/Projects/api/node_modules
        (kept node_modules for 2 active repos)
        ### 3. Package-manager caches (prune unreferenced only)
        [DRY]     prune:pnpm  Unused packages in the pnpm store (size not known until it runs)
        [DRY]     prune:npm  The whole npm cache, which downloads again when needed (size not known until it runs)
        ### 3c. App caches (each app's folder in ~/Library/Caches)
        [DRY]    1.4 GB  \(home)/Library/Caches/com.example.Editor
        [DRY]    310.0 MB  \(home)/Library/Caches/deno
        ### 3d. More tool caches
        [DRY]    2.4 GB  \(home)/Library/Developer/Xcode/DerivedData
        [DRY]    180.0 MB  \(home)/Library/Caches/pip
        ### 4. Time Machine local snapshots
        2 local snapshot(s) present (pinning freed space).
        ALERT: 2 TM snapshot(s) pin freed space. Reclaim now: sudo tmutil thinlocalsnapshots / 999999999999 4
        Free space now: 101Gi avail (77% used)
        """.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return CacheReview.build(lines: lines, banner: "storage-auto-clean.sh | mode=deep | DRY RUN | 2026-11-11 08:00:00",
                                 modified: { _ in Date().addingTimeInterval(-9 * 86_400) }).rows
    }

    /// A Mac at 98 percent full whose last day lost 110 GB, for looking at the Disk screen's worst case.
    public static func disk() -> (usage: DiskUsage, runway: DiskRunway, reason: String, tasks: [StorageTask]) {
        let now = Date()
        return (DiskUsage(totalBytes: 494_000_000_000, freeBytes: 10_000_000_000),
                DiskRunway(daysToFull: 0.1, points: 4),
                "Worked out from the last 2 days (4 cleanups' figures), which are falling faster than the long trend.",
                [StorageTask(kind: .storageClean, reclaimableBytes: 3_600_000_000, measuredAt: now.addingTimeInterval(-3_600),
                             detail: "Deep preview: 30 folders in 5 projects, 2 app caches."),
                 StorageTask(kind: .janitor, reclaimableBytes: 2_500_000_000, measuredAt: now.addingTimeInterval(-50_000),
                             detail: "70 old items can go to the Trash."),
                 StorageTask(kind: .tempClean, reclaimableBytes: 597_000_000, measuredAt: now.addingTimeInterval(-72_000),
                             detail: "15 items ready to clear."),
                 StorageTask(kind: .spotlight, reclaimableBytes: nil, measuredAt: now.addingTimeInterval(-72_000),
                             detail: "13 developer folders still indexed.")])
    }

    /// What a preview of Time Machine's local snapshots shows: two days of hourly snapshots and one of macOS's own.
    public static func timeMachine() -> StorageRows {
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let now = Date()
        var lines = ["FREE_BEFORE 51Gi"]
        for hours in [1, 2, 3, 4, 26, 27, 28, 50] {
            lines.append("SNAPSHOT \(stamp.string(from: now.addingTimeInterval(-Double(hours) * 3_600)))")
        }
        lines.append("OSSNAPSHOT com.apple.os.update-0123456789ABCDEF")
        return TimeMachineReview.build(lines: lines, now: now).rows
    }

    /// What a preview of unused apps shows: the apps by how long since they were opened.
    public static func unusedApps() -> StorageRows {
        func app(_ name: String, _ opened: String?, _ items: [(String, String)]) -> [String] {
            var lines = ["### APP: \(name)   (bundle: com.example.\(name.replacingOccurrences(of: " ", with: "")))"]
            lines.append("[APP]     /Applications/\(name).app")
            if let opened { lines.append("last launched (Spotlight): \(opened)") }
            lines.append("[DRY]       \(items[0].0)  /Applications/\(name).app")
            for item in items.dropFirst() { lines.append("[DRY]       \(item.0)  \(home)/Library/\(item.1)") }
            return lines
        }
        let day = { (days: Int) in DateFormatter.fixtureDay.string(from: Date().addingTimeInterval(-Double(days) * 86_400)) }
        var lines: [String] = []
        lines += app("Old Editor", day(520), [("1.2 GB", ""), ("640 MB", "Application Support/Old Editor"), ("90 MB", "Caches/com.example.OldEditor"), ("12 KB", "Preferences/com.example.OldEditor.plist")])
        lines += app("Screen Recorder", day(410), [("310 MB", ""), ("4.1 GB", "Application Support/Screen Recorder"), ("22 MB", "Caches/com.example.ScreenRecorder")])
        lines += app("Photo Tool", day(230), [("880 MB", ""), ("120 MB", "Containers/com.example.PhotoTool")])
        lines += app("Video Converter", day(200), [("250 MB", ""), ("30 MB", "Caches/com.example.VideoConverter")])
        lines += ["### APP: Electron Notes   (bundle: com.example.electronnotes)", "[APP]     /Applications/Electron Notes.app", "last launched (Spotlight): \(day(450))",
                  "[DRY]       180 MB  /Applications/Electron Notes.app", "[DRY]       60 MB  \(home)/Library/Caches/com.example.electronnotes",
                  "[LEFT]      2.0 GB  \(home)/Library/Application Support/Electron  —  it carries the app's name, but another program may use the same name",
                  "[LEFT]      40 MB  \(home)/Library/Group Containers/group.example.shared  —  another app shares this group container"]
        lines += app("Chat Client", nil, [("410 MB", ""), ("1.0 GB", "Application Support/Chat Client")])
        lines += ["### APP: Notes Sync   (bundle: com.example.NotesSync)", "[APP]     /Applications/Notes Sync.app", "last launched (Spotlight): \(day(300))",
                  "[DRY]       95 MB  /Applications/Notes Sync.app", "  ⚠ Notes Sync appears to be RUNNING — quit it first; skipping this app."]
        // apps that cannot be judged are listed and kept, with the reason
        lines += ["### APP: VPN Client   (bundle: com.example.VPNClient)", "[APP]     /Applications/VPN Client.app", "last launched (Spotlight): \(day(260))",
                  "[KEEP]    Has a system extension"]
        lines += ["### APP: Menu Tool   (bundle: com.example.MenuTool)", "[APP]     /Applications/Menu Tool.app",
                  "[KEEP]    macOS has no record of when this was last opened"]
        return UnusedReview.apps(lines: lines.map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// The detail of Unused Apps with its groups open: an app with its files and the apps inside it, an app with a
    /// left-in-place folder and a shared container, and an app that is kept, with the sentence over the table about
    /// what could not be read.
    public static func unusedAppsDetail() -> StorageRows {
        let day = { (days: Int) in DateFormatter.fixtureDay.string(from: Date().addingTimeInterval(-Double(days) * 86_400)) }
        let lines = [
            "### APP: Old Editor   (bundle: com.example.OldEditor)", "[APP]     /Applications/Old Editor.app", "last launched (Spotlight): \(day(520))",
            "contains: 2 other app(s) inside it, removed with it: Updater.app; Crash Reporter.app (their own settings and data are left in place)",
            "[DRY]       1.2 GB  /Applications/Old Editor.app", "[DRY]       640 MB  \(home)/Library/Application Support/Old Editor",
            "[DRY]       90 MB  \(home)/Library/Caches/com.example.OldEditor", "[DRY]       12 KB  \(home)/Library/Preferences/com.example.OldEditor.plist",
            "### APP: Electron Notes   (bundle: com.example.electronnotes)", "[APP]     /Applications/Electron Notes.app", "last launched (Spotlight): \(day(450))",
            "[DRY]       180 MB  /Applications/Electron Notes.app", "[DRY]       60 MB  \(home)/Library/Caches/com.example.electronnotes",
            "[LEFT]      2.0 GB  \(home)/Library/Application Support/Electron  —  it carries the app's name, but another program may use the same name",
            "[LEFT]      40 MB  \(home)/Library/Group Containers/group.example.shared  —  another app shares this group container",
            "[LEFT]      8 MB  \(home)/Library/Group Containers/group.com.example.electronnotes  —  its name matches the app, but the app does not declare it, so nothing shows it is the app's",
            "### APP: VPN Client   (bundle: com.example.VPNClient)", "[APP]     /Applications/VPN Client.app", "last launched (Spotlight): \(day(260))",
            "[KEEP]    Has a system extension",
            "[CONTAINERS-KEPT] the settings of Broken Tool.xpc could not be read; an app folder that is configured is not there: /Volumes/Apps/Applications",
        ]
        return UnusedReview.apps(lines: lines)
    }

    /// Every app kept because which apps open at login cannot be checked yet: nothing run, or the last run could not read them.
    public static func unusedAppsLoginFirst(unreadable: Bool) -> StorageRows {
        let reason = unreadable
            ? "Which apps open at login can't be checked yet: the last Login & Startup Items check could not read your Login Items. Run it from the Mac Analyzers app, where macOS can ask for permission, then preview again"
            : "Which apps open at login can't be checked yet: run Login & Startup Items first, then preview again"
        var lines: [String] = []
        for (name, days) in [("Old Editor", 520), ("Screen Recorder", 410), ("Photo Tool", 230)] {
            lines += ["### APP: \(name)   (bundle: com.example.\(name.replacingOccurrences(of: " ", with: "")))", "[APP]     /Applications/\(name).app",
                      "last launched (Spotlight): \(DateFormatter.fixtureDay.string(from: Date().addingTimeInterval(-Double(days) * 86_400)))", "[KEEP]    \(reason)"]
        }
        return UnusedReview.apps(lines: lines)
    }

    /// What a preview of old recordings shows with several sources: one tab each, the recordings by the day they were
    /// made, and a Zoom meeting that is kept because Zoom has not converted it.
    public static func recordings() -> StorageRows {
        recordingsRun(extraSources: [])
    }

    /// More than six sources: the five largest keep a tab and the rest share Other Folders.
    public static func recordingsMany() -> StorageRows {
        recordingsRun(extraSources: [("loomTemporary", "Loom (Unsent Videos)", "\(home)/Movies/Loom/Temporary", ["8f3a21", "c19d0e"]),
                                     ("custom", "Podcast", "\(home)/Audio/Podcast", ["Episode 12", "Episode 13", "Episode 14"]),
                                     ("custom", "Interviews", "\(home)/Audio/Interviews", ["Maria Lopes", "Chen Wei"]),
                                     ("custom", "Lectures", "\(home)/Audio/Lectures", ["Week 3", "Week 4"])])
    }

    private static func recordingsRun(extraSources: [(id: String, title: String, path: String, names: [String])]) -> StorageRows {
        let day: Double = 86_400
        var lines: [String] = []
        var dates: [String: Date] = [:]
        func add(_ line: String, path: String, daysAgo: Double) {
            lines.append(line)
            dates[path] = Date().addingTimeInterval(-daysAgo * day)
        }
        func entry(_ tag: String, _ size: String, _ path: String) -> String { "\(tag)     \(size)  \(path)" }
        let zoom = "\(home)/Documents/Zoom"
        lines.append("### Source\tzoom\tZoom\t\(zoom)")
        for (index, meeting) in [("2026-08-12 13.38.03", "Design Review"), ("2026-08-12 16.02.40", "Client Call"),
                                 ("2026-09-03 09.30.11", "Standup"), ("2026-09-18 11.15.00", "Hiring Sync")].enumerated() {
            let path = "\(zoom)/\(meeting.0) \(meeting.1)"
            add(entry("[DRY]", ["1.4 GB", "880.0 MB", "210.0 MB", "640.0 MB"][index], path), path: path, daysAgo: 110 - Double(index) * 9)
        }
        add(entry("[DRY]", "320.0 MB", "\(zoom)/loose-recording.mp4"), path: "\(zoom)/loose-recording.mp4", daysAgo: 120)
        lines.append("[KEEP]     540.0 MB  \(zoom)/2026-09-20 15.45.12 Board Meeting  —  Zoom has not converted this recording yet. Open it in Zoom first.")
        let shots = "\(home)/Desktop/Screenshots"
        lines.append("### Source\tscreenRecordings\tScreen Recordings\t\(shots)")
        for (index, name) in ["Screen Recording 2026-08-12 at 10.14.02.mov", "Screen Recording 2026-09-01 at 17.20.45.mov", "Screen Recording 2026-09-14 at 09.02.31.mov"].enumerated() {
            let path = "\(shots)/\(name)"
            add(entry("[DRY]", ["1.1 GB", "430.0 MB", "260.0 MB"][index], path), path: path, daysAgo: 100 - Double(index) * 20)
        }
        let whisper = "\(home)/superwhisper/recordings"
        lines.append("### Source\tsuperwhisper\tSuperWhisper\t\(whisper)")
        lines.append("  [WARN] \(RecordingSourceCatalog.definition("superwhisper")?.warning ?? "")")
        for (index, stamp) in ["1790007979", "1790094379", "1790180779", "1790267179"].enumerated() {
            let path = "\(whisper)/\(stamp)"
            add(entry("[DRY]", "\(12 + index * 3).0 MB", path), path: path, daysAgo: 95 + Double(index) * 6)
        }
        for source in extraSources {
            lines.append("### Source\t\(source.id)\t\(source.title)\t\(source.path)")
            for (index, name) in source.names.enumerated() {
                let path = "\(source.path)/\(name)"
                add(entry("[DRY]", "\(40 + index * 25).0 MB", path), path: path, daysAgo: 130 + Double(index) * 11)
            }
        }
        if extraSources.isEmpty {
            let notes = "\(home)/Notes/audio"
            lines.append("### Source\tcustom\taudio\t\(notes)")
            for (index, name) in ["Lecture 4", "Lecture 5"].enumerated() {
                let path = "\(notes)/\(name)"
                add(entry("[DRY]", "\(180 + index * 40).0 MB", path), path: path, daysAgo: 200 + Double(index) * 7)
            }
        }
        return UnusedReview.recordings(lines: lines, info: { dates[$0] })
    }

    public static func downloads() -> StorageRows {
        var lines = ["### Downloads (untouched 60+ days)"]
        let documents = ["Invoice March.pdf", "Tax Notes.docx", "Lease.pdf", "Receipt 4821.pdf", "Meeting Notes.txt"]
        for (index, name) in documents.enumerated() { lines.append("[DRY] \(index + 1) MB  \(home)/Downloads/\(name)") }
        lines += ["[DRY] 2.5 GB  \(home)/Downloads/2025", "[DRY] 640.0 MB  \(home)/Downloads/Setup.dmg",
                  "[DRY] 3 MB  \(home)/Downloads/photo.jpg",
                  // documents that exist only in iCloud: shown with their real size, never offered
                  "[CLOUD] 120.0 MB  \(home)/Downloads/Thesis draft.docx", "[CLOUD] 48.0 MB  \(home)/Downloads/Contract signed.pdf",
                  "### Screenshots (untouched 60+ days)"]
        for index in 0..<12 { lines.append("[CLOUD] 26 KB  \(home)/Desktop/Screenshots/Screenshot \(index).png") }
        lines.append("[SKIP] kept by pattern  \(home)/Downloads/keep-me.zip")
        return DownloadReview.build(lines: lines, info: { path in
            (Date().addingTimeInterval(-Double(70 + path.count) * 86_400), !path.contains("."))
        }).rows
    }

    public static func temp() -> StorageRows {
        let lines = """
        ### 1. Overview
        Free space now: 113.6 GB
        Temp on disk: 511.5 MB  |  Inside mounted images: 0 KB  |  A plain du would show: 511.5 MB
        AI agent folders: 11.1 GB  |  Live Claude Code sessions: 1  |  Codex running: no  |  Claude app running: yes
        ### 3. /tmp
        [DRY] 27.4 MB  /private/tmp/node-compile-cache
        [RECENT] 384 KB  /private/tmp/d.txt
        ↳ changed in the last 24h
        ### 6. AI agents — Claude Code
        [HISTORY] 3.6 GB  \(home)/.claude/projects
        ↳ session transcripts — Claude Code deletes them after 30 days (cleanupPeriodDays); auto-memory is never deleted
        [MANAGED] 27.5 MB  \(home)/.claude/file-history
        ↳ Claude Code prunes this itself after 30 days
        ### 7. AI agents — Codex
        [DRY] 34.4 MB  \(home)/.codex/.tmp/marketplaces
        ### 9. AI agents — npx-run tools & MCP servers
        [DRY] 129.1 MB  \(home)/.npm/_npx/bef22f83919465d9
        ↳ codemod
        [IN USE] 70.0 MB  \(home)/.npm/_npx/d66c5096c7023bfb
        ↳ a running MCP server or tool uses it · shadcn
        ### 11. Managed by macOS (never touched)
        [MANAGED] 1.6 GB  /private/var/db/diagnostics
        ↳ unified logs — macOS ages them out by size and date
        """.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return TempReview.build(from: TempCleanParser.parse(runHeader: "temp-clean | DRY RUN | 2026-11-11 08:00:00", lines: lines)).rows
    }

    // MARK: - what an apply left in the log (a finished run's results)

    public static func cachesRun() -> StorageRows {
        let lines = """
        roots=\(home)/Projects  cache>3d
        ### 1. Build caches not written in >3 days (regenerable)
        [DELETED]      2.0 GB  \(home)/Projects/web-app/apps/mobile/.next
        [DELETED]    620.0 MB  \(home)/Projects/web-app/.next
        [FAILED]     410.0 MB  \(home)/Projects/api/.turbo
        ### 3c. App caches (each app's folder in ~/Library/Caches)
        [DELETED]    1.4 GB  \(home)/Library/Caches/com.example.Editor
        ### 3. Package-manager caches (prune unreferenced only)
        running: pnpm store prune
        done: pnpm store prune
        running: brew cleanup --prune=all -s
        failed: brew cleanup --prune=all -s (exit 1)
        [SKIP]    prune:npm  not in the reviewed list
        ### 3.5 Docker prune
        OrbStack already running — pruning, will leave it running.
        running: docker system prune -f
        done: docker system prune -f
        ### 4. Time Machine local snapshots
        thinned 2 local snapshot(s) — freed space now realized in df.
        Free space now: 108Gi avail (74% used)
        """.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return CacheReview.build(lines: lines, banner: "storage-auto-clean.sh | mode=daily | APPLY | 2026-11-11 08:00:00",
                                 results: true).rows
    }

    public static func downloadsRun() -> StorageRows {
        let lines = [
            "### Downloads (untouched 60+ days)",
            "[TRASHED] 3 MB  \(home)/Downloads/photo.jpg  ->  \(home)/.Trash/photo.jpg",
            "[TRASHED] 2.5 GB  \(home)/Downloads/2025  ->  \(home)/.Trash/2025",
            "[FAILED] 12 MB  \(home)/Downloads/locked.zip",
            "### Screenshots (untouched 60+ days)",
            "[TRASHED] 0 KB  \(home)/Desktop/Screenshots/Screenshot 1.png  ->  \(home)/.Trash/Screenshot 1.png",
        ]
        return DownloadReview.build(lines: lines, results: true).rows
    }
}

private extension DateFormatter {
    static let fixtureDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let fixtureMonth: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM yyyy"; return f
    }()
}
