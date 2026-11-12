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

/// One app in a `cleanup.sh --stale-apps` run, with every file that goes with it, one by one.
public struct UnusedApp: Sendable, Equatable {
    public let name: String
    public let bundleID: String?
    /// The app bundle's path: the key of the reviewed list.
    public var path: String
    public var lastOpened: Date?
    /// The bundle first, then each file that goes with it (Application Support, Caches, Preferences…) with its size.
    public var footprint: [(path: String, bytes: Int64)] = []
    /// Files that match the app but are NOT taken, with why (a shared name, a group container another app shares).
    public var left: [(path: String, bytes: Int64, why: String)] = []
    /// What an apply did, one entry per path.
    public var trashed: [(path: String, bytes: Int64)] = []
    public var failed: [(path: String, why: String)] = []
    public var isRunning = false
    /// How many other apps are inside this one (they go with it); 0 when none.
    public var nestedCount = 0
    /// Why the script keeps the app (it runs on its own, macOS has no record…); nil when it can be removed.
    public var keepReason: String?

    public init(name: String, bundleID: String?, path: String) { self.name = name; self.bundleID = bundleID; self.path = path }

    public static func == (lhs: UnusedApp, rhs: UnusedApp) -> Bool { lhs.path == rhs.path && lhs.footprint.count == rhs.footprint.count }
}

/// What a run of unused apps (or old recordings) would do, or did, as the rows Storage screens share.
public enum UnusedReview {

    // MARK: - apps

    /// The sentence over the table when the script could not check which apps open at login.
    /// The last audit ran but could not list the System Settings login items.
    public static let loginUnreadableNote = "The last Login & Startup Items check could not read your Login Items, so which apps open at login can't be checked yet. Run that check from Mac Analyzers, where macOS can ask for permission, then preview again."
    /// What the "does it start on its own" check reads, and what it cannot see: said once, so a person can weigh a row.
    public static let checkLimitsNote = "Whether an app starts on its own is read from your launch entries and the commands and scripts in them that open it, your Login Items, and what is inside the app. It cannot see a script that builds the app's name from parts, Shortcuts, Automator, cron, or another program that opens the app only when it needs it."
    /// Why no shared container was taken, when something could not be read: the engine's `[CONTAINERS-KEPT]` line.
    public static func containersKeptNote(_ causes: String) -> String {
        "Something could not be read, so no container another app might share is taken (\(causes)). Fix that and preview again."
    }
    public static let loginCheckNote = "Which apps open at login can only be read from the Login & Startup Items check, and it has not run today. Run it, then preview again."

    /// The apps of a whole `cleanup.sh --stale-apps` block. Each app is a group of rows: the app itself and every
    /// file that goes with it, with sizes, so what a tick takes is in front of the person. `results` builds what an
    /// apply did (moved to the Trash, couldn't move) instead.
    public static func apps(lines: [String], results: Bool = false, now: Date = Date()) -> StorageRows {
        var apps: [UnusedApp] = []
        var current: UnusedApp?
        func close() { if let app = current { apps.append(app) }; current = nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var keptCauses: String?
        for line in lines {
            if line.hasPrefix("[CONTAINERS-KEPT]") {
                keptCauses = String(line.dropFirst("[CONTAINERS-KEPT]".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("### APP:") {
                close()
                let body = String(line.dropFirst("### APP:".count)).trimmingCharacters(in: .whitespaces)
                var name = body, bid: String?
                if let open = body.range(of: "   (bundle: ") {
                    name = String(body[..<open.lowerBound])
                    let rest = body[open.upperBound...].dropLast(body.hasSuffix(")") ? 1 : 0)
                    bid = rest == "unknown" ? nil : String(rest)
                }
                current = UnusedApp(name: name, bundleID: bid, path: "")
                continue
            }
            guard current != nil else { continue }
            if line.hasPrefix("[APP]") {
                current?.path = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("last launched (Spotlight):") {
                let day = String(line.dropFirst("last launched (Spotlight):".count)).trimmingCharacters(in: .whitespaces)
                current?.lastOpened = formatter.date(from: String(day.prefix(10)))
            } else if line.hasPrefix("contains:") {
                let digits = line.dropFirst("contains:".count).trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
                current?.nestedCount = Int(digits) ?? 0
            } else if line.contains("appears to be RUNNING") {
                current?.isRunning = true
            } else if line.hasPrefix("[KEEP]") {
                current?.keepReason = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("[LEFT]"), let item = sized(line, tag: "[LEFT]") {
                let pieces = item.rest.components(separatedBy: "  —  ")
                current?.left.append((pieces[0], item.bytes, pieces.count > 1 ? pieces[1] : "it may belong to something else"))
            } else if line.hasPrefix("[TRASHED]"), let item = sized(line, tag: "[TRASHED]") {
                let path = ReceiptIdentity.split(item.rest).text.components(separatedBy: "  ->  ")[0]
                current?.trashed.append((path, item.bytes))
            } else if line.hasPrefix("[FAILED]") {
                let body = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                let pieces = body.components(separatedBy: "  —  ")
                current?.failed.append((pieces[0], pieces.count > 1 ? pieces[1] : "it could not be moved"))
            } else if line.hasPrefix("[DRY]") || line.hasPrefix("[item]"), let item = sized(line, tag: line.hasPrefix("[DRY]") ? "[DRY]" : "[item]") {
                current?.footprint.append((item.rest, item.bytes))
            }
        }
        close()
        apps = apps.filter { !$0.path.isEmpty }

        var rows: [StorageRow] = []
        var notes: [String] = []
        for app in apps {
            if results {
                for item in app.trashed {
                    rows.append(StorageRow(id: item.path, category: UnusedAppCategory.apps.rawValue, group: app.name, title: Self.title(of: item.path, app: app),
                                           detail: "\(Names.Unused.movedToTrash) · \(StorageLog.short(item.path))", bytes: item.bytes > 0 ? item.bytes : nil))
                }
                for item in app.failed {
                    rows.append(StorageRow(id: item.path, category: UnusedAppCategory.apps.rawValue, group: app.name, title: Self.title(of: item.path, app: app),
                                           detail: "\(Names.Unused.couldNotMove) · \(item.why)"))
                }
                continue
            }
            let opened = app.lastOpened.map { "Last opened \(Self.date($0))" } ?? (app.keepReason == nil ? "Not opened since it was installed" : "No record of use")
            if let keep = app.keepReason ?? (app.isRunning ? Names.Unused.runningKept : nil) {
                if keep.hasPrefix("Which apps open at login can't be checked") {
                    let note = keep.contains("could not read your Login Items") ? loginUnreadableNote : loginCheckNote
                    if !notes.contains(note) { notes.append(note) }
                }
                rows.append(StorageRow(id: app.path, category: UnusedAppCategory.apps.rawValue, group: app.name, title: app.name,
                                       detail: opened, bytes: nil, valueText: "Kept", iconPath: app.path, keptReason: keep))
                continue
            }
            for (index, item) in app.footprint.enumerated() {
                let isBundle = item.path == app.path || index == 0
                rows.append(StorageRow(id: item.path, category: UnusedAppCategory.apps.rawValue, group: app.name,
                                       title: isBundle ? app.name : Self.title(of: item.path, app: app),
                                       detail: isBundle ? "\(opened) · \(StorageLog.short(item.path))" + (app.nestedCount > 0 ? " · Contains \(app.nestedCount) other \(app.nestedCount == 1 ? "app" : "apps")" : "") : StorageLog.short(item.path),
                                       bytes: item.bytes, iconPath: isBundle ? item.path : nil))
            }
            for item in app.left {
                rows.append(StorageRow(id: item.path, category: UnusedAppCategory.apps.rawValue, group: app.name,
                                       title: Self.title(of: item.path, app: app), detail: StorageLog.short(item.path), bytes: item.bytes,
                                       keptReason: "\(Names.Unused.leftInPlace): \(item.why)"))
            }
        }
        if let keptCauses, !results { notes.append(containersKeptNote(keptCauses)) }
        if !results && !rows.isEmpty { notes.append(checkLimitsNote) }
        return StorageRows(rows, notes: notes)
    }

    /// "Application Support", "Group Containers", "Caches": the Library folder a file lives in; the app's name for the app.
    static func title(of path: String, app: UnusedApp) -> String {
        if path == app.path { return app.name }
        let parts = path.split(separator: "/")
        if let at = parts.firstIndex(of: "Library"), parts.indices.contains(at + 1) {
            let kind = String(parts[at + 1])
            if kind == "Preferences", parts.contains("ByHost") { return "Preferences (This Mac)" }
            return kind
        }
        return (path as NSString).lastPathComponent
    }

    private static func date(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }

    /// `[TAG]   12 MB  rest`: the size and what follows it.
    private static func sized(_ line: String, tag: String) -> (bytes: Int64, rest: String)? {
        let rest = String(line.dropFirst(tag.count)).trimmingCharacters(in: .whitespaces)
        guard let range = rest.range(of: #"^[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
              let bytes = ByteSize.parse(String(rest[range]).trimmingCharacters(in: .whitespaces)) else { return nil }
        return (bytes, String(rest[range.upperBound...]))
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
            let isKept = !results && line.hasPrefix("[KEEP]")
            guard isRun || isDone || isKept else { continue }
            let rest = String(line.drop(while: { $0 != "]" }).dropFirst()).trimmingCharacters(in: .whitespaces)
            guard let range = rest.range(of: #"^[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
                  let bytes = ByteSize.parse(String(rest[range]).trimmingCharacters(in: .whitespaces)) else { continue }
            var path = String(rest[range.upperBound...])
            if let label = path.range(of: "   (", options: .backwards), path.hasSuffix(")") { path = String(path[..<label.lowerBound]) }
            if let arrow = path.range(of: "  ->  ") { path = String(path[..<arrow.lowerBound]) }     // a receipt: "path  ->  Trash path  #id=…"
            var keptWhy: String?
            if isKept, let dash = path.range(of: "  —  ") { keptWhy = String(path[dash.upperBound...]); path = String(path[..<dash.lowerBound]) }
            let group = results ? Names.Unused.recordings : (info(path).map { month.string(from: $0) } ?? Names.Download.dateUnknown)
            rows.append(StorageRow(id: path, category: RecordingCategory.recordings.rawValue, group: group,
                                   title: (path as NSString).lastPathComponent,
                                   detail: results ? "\(Names.Unused.removed) · \(StorageLog.short(path))" : StorageLog.short(path),
                                   bytes: bytes, iconPath: results ? nil : path,
                                   keptReason: isKept ? "Kept: \(keptWhy ?? "it cannot be moved")" : nil))
        }
        return StorageRows(rows)
    }
}
