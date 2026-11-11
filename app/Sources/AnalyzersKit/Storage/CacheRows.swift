import Foundation

/// What a folder in a project is, in words a person knows.
public enum CacheKind: String, CaseIterable, Sendable {
    case nextBuild, turbo, buildOutput, vite, svelteKit, nuxt, parcel, nodePackages
    // folders Spotlight audits also meet
    case vendored, pythonCache, pythonEnvironment, rustBuild
    case other

    /// From the folder's own name, which is all the engine reports.
    public init(folder: String) {
        switch folder {
        case ".next": self = .nextBuild
        case ".turbo": self = .turbo
        case "dist", "build": self = .buildOutput
        case ".vite": self = .vite
        case ".svelte-kit": self = .svelteKit
        case ".nuxt": self = .nuxt
        case ".parcel-cache": self = .parcel
        case "node_modules": self = .nodePackages
        case "vendor": self = .vendored
        case "__pycache__": self = .pythonCache
        case ".venv": self = .pythonEnvironment
        case "target": self = .rustBuild
        default: self = .other
        }
    }

    public var title: String {
        switch self {
        case .nextBuild: Names.Cache.nextBuild
        case .turbo: Names.Cache.turbo
        case .buildOutput: Names.Cache.buildOutput
        case .vite: Names.Cache.vite
        case .svelteKit: Names.Cache.svelteKit
        case .nuxt: Names.Cache.nuxt
        case .parcel: Names.Cache.parcel
        case .nodePackages: Names.Cache.nodePackages
        case .vendored: Names.Cache.vendored
        case .pythonCache: Names.Cache.pythonCache
        case .pythonEnvironment: Names.Cache.pythonEnvironment
        case .rustBuild: Names.Cache.rustBuild
        case .other: Names.Cache.other
        }
    }
}

/// How far a cleanup goes.
public enum CacheMode: String, CaseIterable, Identifiable, Sendable {
    case daily, deep
    public var id: String { rawValue }

    public var title: String { self == .daily ? Names.Cache.daily : Names.Cache.deep }

    /// One sentence for the control.
    public var sentence: String {
        switch self {
        case .daily: "Build caches that haven't been written to in days."
        case .deep: "Also node_modules of projects you haven't touched, package-manager caches, and the space Time Machine snapshots hold."
        }
    }

    public var options: JobOptions { JobOptions(deep: self == .deep) }

    public init(options: JobOptions) { self = options.deep ? .deep : .daily }
}

/// The tabs of Caches & Builds.
public enum CacheCategory: String, StorageCategory {
    case projects, appCaches, developerTools

    public var title: String {
        switch self {
        case .projects: Names.StorageTab.projects
        case .appCaches: Names.StorageTab.appCaches
        case .developerTools: Names.StorageTab.developerTools
        }
    }

    public var symbol: String {
        switch self {
        case .projects: "folder"
        case .appCaches: "square.stack.3d.up"
        case .developerTools: "wrench.and.screwdriver"
        }
    }
}

/// What a cleanup of caches and builds would do (or did), as the rows Storage screens
/// share: a project and the folders in it, each app's cache, and the developer tools'
/// caches and cleanups, with the notes that are results rather than rows.
public struct CacheReview: Sendable {
    public let mode: CacheMode
    /// The rows, with the notes that are results rather than rows: the Time Machine sentence
    /// (nothing is sized or ticked until macOS is asked to release it) and "3 projects are in
    /// use and were left alone".
    public let rows: StorageRows
    public let snapshotNote: String?
    public let keptNote: String?
    public let freeSpace: String?

    /// Builds the rows from a run's whole block. `modified` reads a folder's last-write date
    /// (injected so a probe needs no real folders); `results` includes what an apply did
    /// (removed, couldn't remove) instead of only what a preview would do.
    public static func build(lines: [String], banner: String, roots: [String]? = nil, results: Bool = false,
                             modified: (String) -> Date? = { StorageModified.date(of: $0) }) -> CacheReview {
        let roots = roots ?? Self.roots(in: lines)
        var section = ""
        var rows: [StorageRow] = []
        var snapshot: String?
        var kept: String?
        var free: String?
        var notes: [String] = []
        for line in lines {
            if line.hasPrefix("### ") {
                var title = String(line.dropFirst(4))
                if let dot = title.range(of: #"^[\d.]+[a-z]?\.?\s+"#, options: .regularExpression) { title = String(title[dot.upperBound...]) }
                section = title
                continue
            }
            if line.hasPrefix("(kept node_modules") { kept = keptSentence(line); continue }
            if line.hasPrefix("Free space now:") {
                free = String(line.dropFirst(15)).trimmingCharacters(in: .whitespaces); continue
            }
            // the cleanups that are not paths: a preview's `[DRY] prune:<id>` row, and what an apply
            // printed for each (`running: <command>`, `[SKIP] prune:<id>`, the snapshot lines)
            if line.hasPrefix("["), let close = line.firstIndex(of: "]"),
               String(line[line.index(after: line.startIndex)..<close]) == "DRY" {
                let rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("prune:"), let space = rest.firstIndex(of: " ") {
                    rows.append(pruneRow(key: String(rest[..<space]),
                                         summary: String(rest[space...]).trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if results, let row = pruneResult(line) {
                // "running:" then "done:" or "failed:" for one command: the later line is the answer
                if let at = rows.firstIndex(where: { $0.id == row.id }) { rows[at] = row } else { rows.append(row) }
                continue
            }
            if section.hasPrefix("Time Machine") {
                if !line.isEmpty, !line.hasPrefix("[") { notes.append(line) }
                continue
            }
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let tag = String(line[line.index(after: line.startIndex)..<close])
            let rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard let status = StoragePathItem.Status(rawValue: tag), results || status == .dry,
                  let sizeRange = rest.range(of: #"^~?[\d.]+ [KMGT]?B\s+"#, options: .regularExpression),
                  let bytes = ByteSize.parse(String(rest[sizeRange]).trimmingCharacters(in: .whitespaces))
            else { continue }
            let path = String(rest[sizeRange.upperBound...])
            rows.append(pathRow(path: path, bytes: bytes, status: status, section: section, roots: roots,
                                lastUsed: results ? nil : modified(path)))
        }
        snapshot = notes.isEmpty ? nil : snapshotSentence(notes.joined(separator: " "))
        return CacheReview(mode: banner.contains("mode=deep") ? .deep : .daily,
                           rows: StorageRows(rows, notes: [kept, snapshot].compactMap { $0 },
                                             facts: free.map { ["free space \($0)"] } ?? []),
                           snapshotNote: snapshot, keptNote: kept, freeSpace: free)
    }

    // MARK: - rows

    static func pathRow(path: String, bytes: Int64, status: StoragePathItem.Status, section: String,
                                roots: [String], lastUsed: Date?) -> StorageRow {
        let outcome: String? = status == .dry ? nil : status.plainLabel
        func detail(_ extra: String?) -> String {
            [outcome, extra, StorageLog.short(path)].compactMap { $0 }.joined(separator: " · ")
        }
        let used = StorageLog.ago(lastUsed).map { "Last used \($0)" }
        let lower = section.lowercased()
        if lower.hasPrefix("app caches") {
            return StorageRow(id: path, category: CacheCategory.appCaches.rawValue, group: nil,
                              title: appName((path as NSString).lastPathComponent), detail: detail(used),
                              bytes: bytes, iconPath: path)
        }
        if lower.hasPrefix("tool caches") || lower.hasPrefix("more tool caches") || lower.hasPrefix("extra cache") {
            return StorageRow(id: path, category: CacheCategory.developerTools.rawValue, group: Names.StorageTab.toolCaches,
                              title: toolName(path), detail: detail(used), bytes: bytes, iconPath: path)
        }
        // projects: build caches, Turborepo entries and node_modules
        let project = projectPath(of: path, roots: roots)
        let projectName = (project as NSString).lastPathComponent
        let relative = path.hasPrefix(project + "/") ? String(path.dropFirst(project.count + 1)) : (path as NSString).lastPathComponent
        let kind = CacheKind(folder: (path as NSString).lastPathComponent)
        let isEntry = lower.hasPrefix("turborepo")
        let folder = (relative as NSString).deletingLastPathComponent
        let title: String
        if isEntry {
            title = "Turborepo Entry \((path as NSString).lastPathComponent.prefix(8))"
        } else if folder.isEmpty {
            title = kind.title
        } else {
            title = "\(folder) · \(kind.title)"
        }
        return StorageRow(id: path, category: CacheCategory.projects.rawValue, group: projectName, title: title,
                          detail: detail(used), bytes: bytes, iconPath: path)
    }

    private static func pruneWords(_ id: String) -> (title: String, group: String) {
        switch id {
        case "pnpm": (Names.Prune.pnpm, Names.StorageTab.packageManagers)
        case "npm": (Names.Prune.npm, Names.StorageTab.packageManagers)
        case "brew": (Names.Prune.brew, Names.StorageTab.packageManagers)
        case "simulators": (Names.Prune.simulators, Names.StorageTab.xcodeSimulators)
        case "docker": (Names.Prune.docker, Names.StorageTab.docker)
        case "snapshots": (Names.Prune.snapshots, Names.StorageTab.timeMachine)
        default: (id, Names.StorageTab.developerTools)
        }
    }

    private static func pruneRow(key: String, summary: String) -> StorageRow {
        let id = String(key.dropFirst("prune:".count))
        let words = pruneWords(id)
        return StorageRow(id: key, category: CacheCategory.developerTools.rawValue, group: words.group, title: words.title,
                          detail: summary, bytes: nil, valueText: "When Applied")
    }

    /// What an apply did for one of those cleanups, from the line it printed; nil for any other line.
    static func pruneResult(_ line: String) -> StorageRow? {
        func row(_ id: String, _ outcome: String, _ detail: String) -> StorageRow {
            let words = pruneWords(id)
            return StorageRow(id: "prune:\(id)", category: CacheCategory.developerTools.rawValue, group: words.group,
                              title: words.title, detail: detail, bytes: nil, valueText: outcome)
        }
        let known: [(String, String, String)] = [
            ("pnpm store prune", "pnpm", "Unused packages were removed from the pnpm store."),
            ("npm cache clean", "npm", "The npm cache was emptied; it downloads again when needed."),
            ("brew cleanup", "brew", "Old Homebrew versions and downloads were removed."),
            ("xcrun simctl delete unavailable", "simulators", "Simulators whose runtime is gone were removed."),
            ("docker system prune", "docker", "Unused containers, networks and images were removed."),
        ]
        for prefix in ["running: ", "done: ", "failed: "] where line.hasPrefix(prefix) {
            let command = String(line.dropFirst(prefix.count))
            guard let hit = known.first(where: { command.hasPrefix($0.0) }) else { return nil }
            switch prefix {
            case "done: ": return row(hit.1, Names.Prune.ran, hit.2)
            case "failed: ":
                let code = command.range(of: #"\(exit (\d+)\)"#, options: .regularExpression).map { String(command[$0].filter(\.isNumber)) }
                return row(hit.1, Names.Prune.couldNotRun,
                           "It ran but reported an error\(code.map { " (exit \($0))" } ?? ""), so it may not have finished. The raw output has the details.")
            default: return row(hit.1, Names.Prune.started, "It started; the log doesn't say how it ended.")
            }
        }
        if line.hasPrefix("["), let close = line.firstIndex(of: "]"),
           String(line[line.index(after: line.startIndex)..<close]) == "SKIP" {
            let rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("prune:"), let space = rest.firstIndex(of: " ") {
                let id = String(rest[rest.index(rest.startIndex, offsetBy: 6)..<space])
                return row(id, Names.Prune.skipped, "It wasn't ticked in the review, so it didn't run.")
            }
        }
        if line.hasPrefix("thinned "), let range = line.range(of: #"\d+"#, options: .regularExpression) {
            let count = Int(line[range]) ?? 0
            return row("snapshots", Names.Prune.ran,
                       "\(count) Time Machine local \(count == 1 ? "snapshot was" : "snapshots were") thinned. Your backups are not touched.")
        }
        if line.contains("snapshot thin needs the tmutil-thin sudoers rule") {
            return row("snapshots", Names.Prune.couldNotRun,
                       "Thinning needs a one-time permission. The space stays reclaimable until macOS frees it.")
        }
        return nil
    }

    /// The folders the engine sweeps, from the run's own settings line (`roots=/a /b  cache>3d …`).
    public static func roots(in lines: [String]) -> [String] {
        guard let line = lines.first(where: { $0.hasPrefix("roots=") }) else { return [] }
        var text = String(line.dropFirst("roots=".count))
        if let end = text.range(of: "  ") { text = String(text[..<end.lowerBound]) }
        return text.split(separator: " ").map(String.init)
    }

    /// The project folder: the first folder under a swept root, else (when the roots are unknown)
    /// through the first part after "Projects/", else the folder that holds the cache.
    static func projectPath(of path: String, roots: [String]) -> String {
        for root in roots {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if path.hasPrefix(prefix), let first = path.dropFirst(prefix.count).split(separator: "/").first {
                return prefix + first
            }
        }
        if let range = path.range(of: "Projects/") {
            let tail = path[range.upperBound...]
            if let first = tail.split(separator: "/").first {
                return String(path[..<range.upperBound]) + first
            }
        }
        return (path as NSString).deletingLastPathComponent
    }

    // MARK: - words

    private static func appName(_ folder: String) -> String {
        // com.vendor.App → App; plain names stay
        let parts = folder.split(separator: ".")
        if parts.count >= 3, ["com", "org", "io", "net"].contains(String(parts[0])) { return String(parts[parts.count - 1]) }
        return folder
    }

    private static func toolName(_ path: String) -> String {
        let p = path.lowercased()
        let known: [(String, String)] = [
            ("/library/caches/pip", Names.ToolCacheName.pip), ("/.cache/uv", Names.ToolCacheName.uv),
            ("/.cargo/registry", Names.ToolCacheName.cargo), ("/.gradle/caches", Names.ToolCacheName.gradle),
            ("/xcode/deriveddata", Names.ToolCacheName.derivedData), ("/.bun/install/cache", Names.ToolCacheName.bun),
            ("/.cipd-cache-dir", Names.ToolCacheName.cipd), ("/pkg/mod", Names.ToolCacheName.goModules),
            ("/.android/avd", Names.ToolCacheName.androidSnapshots), ("aerial", Names.ToolCacheName.aerials),
        ]
        return known.first { p.contains($0.0) }?.1 ?? (path as NSString).lastPathComponent
    }

    private static func snapshotSentence(_ note: String) -> String? {
        if let range = note.range(of: #"\d+"#, options: .regularExpression), let count = Int(note[range]) {
            let noun = count == 1 ? "snapshot holds" : "snapshots hold"
            return "\(count) Time Machine \(noun) space you freed. A deep cleanup asks macOS to release it."
        }
        return note.contains("No local snapshots") ? nil : "Time Machine snapshots may hold space you freed."
    }

    private static func keptSentence(_ note: String) -> String? {
        guard let range = note.range(of: #"\d+ active"#, options: .regularExpression),
              let count = Int(note[range].split(separator: " ")[0]) else { return nil }
        return count == 1 ? "1 project is in use, so its node_modules was left alone."
                          : "\(count) projects are in use, so their node_modules were left alone."
    }
}

/// File dates, in one place so a probe can stand in for the disk.
public enum StorageModified {
    public static func date(of path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
