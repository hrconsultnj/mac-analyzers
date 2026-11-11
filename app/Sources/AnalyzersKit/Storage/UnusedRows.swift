import Foundation

/// The tab (the only one) of Unused Apps.
public enum UnusedAppCategory: String, StorageCategory {
    case apps
    public var title: String { Names.StorageTab.apps }
    public var symbol: String { "app.badge.checkmark" }
}

/// The tab (the only one) of Old Recordings.
public enum RecordingCategory: String, StorageCategory {
    case recordings
    public var title: String { Names.StorageTab.oldRecordings }
    public var symbol: String { "film" }
}

/// One app in a `cleanup.sh --stale-apps` run, with what goes with it.
public struct UnusedApp: Sendable, Equatable {
    public let name: String
    public let bundleID: String?
    /// The app bundle's path: the key of the reviewed list.
    public let path: String
    public let lastOpened: Date?
    /// Application Support, Caches, Preferences… with their sizes, as the script listed them.
    public let footprint: [(path: String, bytes: Int64)]
    public let totalBytes: Int64
    public let isRunning: Bool
    /// Why the script keeps the app (it runs on its own, macOS has no record…); nil when it can be removed.
    public var keepReason: String?
    public var removed = 0
    public var failed = 0

    public static func == (lhs: UnusedApp, rhs: UnusedApp) -> Bool { lhs.path == rhs.path && lhs.totalBytes == rhs.totalBytes }
}

/// What a run of unused apps (or old recordings) would do, or did, as the rows Storage screens share.
public enum UnusedReview {

    // MARK: - apps

    /// The apps of a whole `cleanup.sh --stale-apps` block. `results` builds what an apply did
    /// (Removed, Couldn't Remove) instead of what a preview would do.
    public static func apps(lines: [String], results: Bool = false, now: Date = Date()) -> StorageRows {
        var apps: [UnusedApp] = []
        var current: (name: String, bid: String?, path: String?, opened: Date?, items: [(String, Int64)], running: Bool, removed: Int, failed: Int, keep: String?)?
        func close() {
            guard let c = current, let path = c.path else { current = nil; return }
            var app = UnusedApp(name: c.name, bundleID: c.bid, path: path, lastOpened: c.opened, footprint: c.items,
                                totalBytes: c.items.reduce(0) { $0 + $1.1 }, isRunning: c.running)
            app.removed = c.removed; app.failed = c.failed; app.keepReason = c.keep
            apps.append(app)
            current = nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for line in lines {
            if line.hasPrefix("### APP:") {
                close()
                let body = String(line.dropFirst("### APP:".count)).trimmingCharacters(in: .whitespaces)
                var name = body, bid: String?
                if let open = body.range(of: "   (bundle: ") {
                    name = String(body[..<open.lowerBound])
                    let rest = body[open.upperBound...].dropLast(body.hasSuffix(")") ? 1 : 0)
                    bid = rest == "unknown" ? nil : String(rest)
                }
                current = (name, bid, nil, nil, [], false, 0, 0, nil)
                continue
            }
            guard current != nil else { continue }
            if line.hasPrefix("[APP]") {
                current?.path = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("last launched (Spotlight):") {
                let day = String(line.dropFirst("last launched (Spotlight):".count)).trimmingCharacters(in: .whitespaces)
                current?.opened = formatter.date(from: String(day.prefix(10)))
            } else if line.contains("appears to be RUNNING") {
                current?.running = true
            } else if line.hasPrefix("[KEEP]") {
                current?.keep = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("[DELETED]") || line.hasPrefix("[TRASHED]") {
                current?.removed += 1
            } else if line.hasPrefix("[FAILED]") {
                current?.failed += 1
            } else if let item = footprintLine(line) {
                current?.items.append(item)
            }
        }
        close()

        var rows: [StorageRow] = []
        for app in apps {
            if results {
                guard app.removed + app.failed > 0 else { continue }
                let outcome = app.failed > 0 ? Names.Unused.couldNotRemove : Names.Unused.removed
                rows.append(StorageRow(id: app.path, category: UnusedAppCategory.apps.rawValue, group: nil, title: app.name,
                                       detail: "\(outcome) · \(StorageLog.short(app.path))", bytes: app.totalBytes > 0 ? app.totalBytes : nil))
                continue
            }
            let days = app.lastOpened.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
            // "Never Opened" only for an app macOS knows and has no use of (the script decided that); an app it
            // cannot judge is kept under its own heading, never called unused
            let group: String
            if app.keepReason != nil { group = app.lastOpened == nil ? Names.Unused.noRecord : DownloadAge(days: days).title }
            else { group = app.lastOpened == nil ? Names.Unused.neverOpened : DownloadAge(days: days).title }
            let opened = app.lastOpened.map { "Last opened \(Self.date($0))" } ?? (app.keepReason == nil ? "Not opened since it was installed" : "No record of use")
            let parts = footprintNames(app)
            var detail = opened
            if !parts.isEmpty { detail += " · " + parts }
            rows.append(StorageRow(id: app.path, category: UnusedAppCategory.apps.rawValue, group: group, title: app.name,
                                   detail: detail, bytes: app.totalBytes > 0 ? app.totalBytes : nil,
                                   valueText: app.totalBytes > 0 ? nil : "Kept", iconPath: app.path,
                                   keptReason: app.keepReason ?? (app.isRunning ? Names.Unused.runningKept : nil)))
        }
        return StorageRows(rows)
    }

    /// "Also removes its Application Support, Caches and Preferences" for the second line.
    static func footprintNames(_ app: UnusedApp) -> String {
        let folders = app.footprint.compactMap { item -> String? in
            guard item.path != app.path else { return nil }
            let comps = item.path.split(separator: "/")
            guard let at = comps.firstIndex(of: "Library"), comps.indices.contains(at + 1) else { return nil }
            return String(comps[at + 1])
        }
        var seen: [String] = []
        for f in folders where !seen.contains(f) { seen.append(f) }
        let names = ListFormatter.localizedString(byJoining: Array(seen.prefix(3)))
        return seen.isEmpty ? "" : "Also removes its \(names)\(seen.count > 3 ? " and more" : "")"
    }

    private static func date(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }

    private static func footprintLine(_ line: String) -> (String, Int64)? {
        guard line.hasPrefix("[DRY]") || line.hasPrefix("[item]") else { return nil }
        let rest = String(line.drop(while: { $0 != "]" }).dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let range = rest.range(of: #"^[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
              let bytes = ByteSize.parse(String(rest[range]).trimmingCharacters(in: .whitespaces)) else { return nil }
        var path = String(rest[range.upperBound...])
        if path.hasPrefix("~") { path = NSHomeDirectory() + path.dropFirst() }
        return (path, bytes)
    }

    // MARK: - recordings

    /// The recording folders of a `cleanup.sh --recordings-older-than` block, grouped by the month
    /// they were last written. `info` reads a folder's date (injected so a probe needs no real folders).
    public static func recordings(lines: [String], results: Bool = false,
                                  info: (String) -> Date? = { StorageFileInfo.read($0).modified }) -> StorageRows {
        let month = DateFormatter()
        month.locale = Locale(identifier: "en_US_POSIX")
        month.dateFormat = "MMMM yyyy"
        var rows: [StorageRow] = []
        for line in lines {
            let isRun = line.hasPrefix("[DRY]"), isDone = results && (line.hasPrefix("[DELETED]") || line.hasPrefix("[TRASHED]"))
            guard isRun || isDone else { continue }
            let rest = String(line.drop(while: { $0 != "]" }).dropFirst()).trimmingCharacters(in: .whitespaces)
            guard let range = rest.range(of: #"^[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
                  let bytes = ByteSize.parse(String(rest[range]).trimmingCharacters(in: .whitespaces)) else { continue }
            var path = String(rest[range.upperBound...])
            if let label = path.range(of: "   (", options: .backwards), path.hasSuffix(")") { path = String(path[..<label.lowerBound]) }
            if let arrow = path.range(of: "  ->  ") { path = String(path[..<arrow.lowerBound]) }     // a receipt: "path  ->  Trash path"
            let group = results ? Names.Unused.recordings : (info(path).map { month.string(from: $0) } ?? Names.Download.dateUnknown)
            rows.append(StorageRow(id: path, category: RecordingCategory.recordings.rawValue, group: group,
                                   title: (path as NSString).lastPathComponent,
                                   detail: results ? "\(Names.Unused.removed) · \(StorageLog.short(path))" : StorageLog.short(path),
                                   bytes: bytes, iconPath: results ? nil : path))
        }
        return StorageRows(rows)
    }
}
