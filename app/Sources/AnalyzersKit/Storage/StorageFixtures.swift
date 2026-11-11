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

    public static func downloads() -> StorageRows {
        var lines = ["### Downloads (untouched 60+ days)"]
        let documents = ["Invoice March.pdf", "Tax Notes.docx", "Lease.pdf", "Receipt 4821.pdf", "Meeting Notes.txt"]
        for (index, name) in documents.enumerated() { lines.append("[DRY] \(index + 1) MB  \(home)/Downloads/\(name)") }
        lines += ["[DRY] 2.5 GB  \(home)/Downloads/2025", "[DRY] 640.0 MB  \(home)/Downloads/Setup.dmg",
                  "[DRY] 3 MB  \(home)/Downloads/photo.jpg", "### Screenshots (untouched 60+ days)"]
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
