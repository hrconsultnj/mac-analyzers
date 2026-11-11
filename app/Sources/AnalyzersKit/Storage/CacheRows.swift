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

    /// Why it is safe to remove, in one sentence.
    public var whySafe: String {
        switch self {
        case .nodePackages, .pythonEnvironment, .vendored:
            "Reinstalled by the package manager the next time the project needs it."
        case .turbo: "Only speeds up builds; a missing entry means one slower build."
        default: "Rebuilt the next time the project builds."
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

/// One folder the preview found: removable, sized, and named for a person.
public struct CacheCandidate: Identifiable, Hashable, Sendable {
    public let path: String
    public let project: String
    public let kind: CacheKind
    public let sizeBytes: Int64
    /// When the folder was last written to; nil when it is already gone.
    public let lastUsed: Date?

    /// The engine's own key for this item — what `--only-paths` is given.
    public var id: String { path }
    public var folderName: String { (path as NSString).lastPathComponent }
    /// "~/Projects/site/.next": the path as a person writes it.
    public var shortPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

/// A project and the folders in it that can go.
public struct CacheProject: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String
    public let items: [CacheCandidate]
    public var id: String { path }
    public var sizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

/// What a cleanup of caches and builds would do, ready for the review table.
public struct CacheReview: Sendable {
    public let mode: CacheMode
    public let projects: [CacheProject]
    /// Things the run would also do that are not folders — shown, never ticked:
    /// the engine runs them only when nothing was unticked.
    public let alsoWhenAllSelected: [String]
    /// The Time Machine sentence, when the run had one.
    public let snapshotNote: String?
    /// "3 projects are in use and were left alone."
    public let keptNote: String?
    public let freeSpace: String?

    public var candidates: [CacheCandidate] { projects.flatMap(\.items) }
    public var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.sizeBytes } }

    /// Builds the review from the run. `modified` reads a folder's last-write
    /// date; it is injected so a probe or a test needs no real folders.
    public static func build(from run: StorageCleanRun, roots: [String] = [],
                             modified: (String) -> Date? = { StorageModified.date(of: $0) }) -> CacheReview {
        let found = run.items.filter { $0.status == .dry }.map { item in
            CacheCandidate(path: item.path, project: projectName(of: item.path, roots: roots, fallback: item.project),
                           kind: CacheKind(folder: item.cacheKind), sizeBytes: item.sizeBytes,
                           lastUsed: modified(item.path))
        }
        var byProject: [String: [CacheCandidate]] = [:]
        var order: [String] = []
        for item in found {
            let root = projectPath(of: item.path, roots: roots)
            if byProject[root] == nil { order.append(root) }
            byProject[root, default: []].append(item)
        }
        let projects = order.map { root in
            let items = byProject[root, default: []].sorted { $0.sizeBytes > $1.sizeBytes }
            return CacheProject(name: items.first?.project ?? (root as NSString).lastPathComponent,
                                path: root, items: items)
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        return CacheReview(mode: run.mode == "deep" ? .deep : .daily, projects: projects,
                           alsoWhenAllSelected: alsoLines(run), snapshotNote: snapshotSentence(run.tmNote),
                           keptNote: keptSentence(run.activeRepoNote), freeSpace: run.freeSpaceAfter)
    }

    /// The folders the engine sweeps, from the run's own settings line
    /// (`roots=/a /b  cache>3d …`). A project is the first folder under one.
    public static func roots(in lines: [String]) -> [String] {
        guard let line = lines.first(where: { $0.hasPrefix("roots=") }) else { return [] }
        var text = String(line.dropFirst("roots=".count))
        if let end = text.range(of: "  ") { text = String(text[..<end.lowerBound]) }
        return text.split(separator: " ").map(String.init)
    }

    static func projectName(of path: String, roots: [String], fallback: String) -> String {
        (projectPath(of: path, roots: roots) as NSString).lastPathComponent.isEmpty
            ? fallback : (projectPath(of: path, roots: roots) as NSString).lastPathComponent
    }

    /// The project folder: the first folder under a swept root, else (when the
    /// roots are unknown) through the first part after "Projects/", else the
    /// folder that holds the cache.
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

    private static func alsoLines(_ run: StorageCleanRun) -> [String] {
        run.packageManagerRaw.compactMap { line in
            if line.contains("pnpm store prune") { return "Remove packages no project uses from the pnpm store." }
            if line.contains("npm cache clean") { return "Empty the npm cache." }
            return nil
        }
    }

    private static func snapshotSentence(_ note: String?) -> String? {
        guard let note else { return nil }
        if let range = note.range(of: #"\d+"#, options: .regularExpression),
           let count = Int(note[range]) {
            let noun = count == 1 ? "snapshot holds" : "snapshots hold"
            return "\(count) Time Machine \(noun) space you freed. A deep cleanup asks macOS to release it."
        }
        return note.contains("No local snapshots") ? nil : "Time Machine snapshots may hold space you freed."
    }

    private static func keptSentence(_ note: String?) -> String? {
        guard let note, let range = note.range(of: #"\d+ active"#, options: .regularExpression),
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
