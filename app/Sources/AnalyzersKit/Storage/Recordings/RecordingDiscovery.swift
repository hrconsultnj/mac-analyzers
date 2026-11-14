import Foundation

/// What discovery may ask the Mac. Injected, so a probe can hand it stand-ins and record every path it is asked about.
///
/// The real readers touch only what needs no permission: the person's own preferences, whether a folder exists in a
/// place macOS does not guard, whether an app is installed, and the NAMES of the mounts under `~/Library/CloudStorage`
/// (never what is inside them).
public struct RecordingReaders: Sendable {
    public var home: String
    /// A string from an app's own preferences.
    public var defaultsString: @Sendable (_ domain: String, _ key: String) -> String?
    /// Whether a folder exists. Never called for a place macOS asks permission for, until the person has clicked.
    public var folderExists: @Sendable (_ path: String) -> Bool
    public var appInstalled: @Sendable (_ name: String) -> Bool
    public var cloudMountNames: @Sendable () -> [String]

    public init(home: String,
                defaultsString: @escaping @Sendable (String, String) -> String?,
                folderExists: @escaping @Sendable (String) -> Bool,
                appInstalled: @escaping @Sendable (String) -> Bool,
                cloudMountNames: @escaping @Sendable () -> [String]) {
        self.home = home
        self.defaultsString = defaultsString
        self.folderExists = folderExists
        self.appInstalled = appInstalled
        self.cloudMountNames = cloudMountNames
    }

    /// The Mac's own answers.
    public static func live() -> RecordingReaders {
        let home = AnalyzersPaths.home.path
        return RecordingReaders(
            home: home,
            defaultsString: { domain, key in CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String },
            folderExists: { path in
                var isFolder: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
            },
            appInstalled: { name in
                ["/Applications", "\(home)/Applications", "/System/Applications"].contains {
                    FileManager.default.fileExists(atPath: "\($0)/\(name).app")
                }
            },
            cloudMountNames: {
                (try? FileManager.default.contentsOfDirectory(atPath: "\(home)/Library/CloudStorage")) ?? []
            })
    }
}

/// Finds where the recording apps on this Mac save, without asking macOS for permission.
///
/// It reads each app's own setting where one exists and never assumes a path it was not told. The places macOS
/// guards (Documents, Desktop, Downloads) are NOT looked at: a source whose folder is there is shown as **Needs
/// Access** until the person clicks Look in Documents (or Desktop), so the question appears when they ask for it.
/// Containers and cloud mounts are never opened at all.
public enum RecordingDiscovery {

    /// The guarded place a path is in (`Documents`, `Desktop`, `Downloads`), or nil.
    public static func protectedArea(_ path: String, home: String) -> String? {
        for area in ["Documents", "Desktop", "Downloads"] {
            let root = "\(home)/\(area)"
            if path == root || path.hasPrefix(root + "/") { return area }
        }
        return nil
    }

    /// Every source on this Mac, in the list's order, then the person's own folders. `saved` carries what was chosen
    /// before (its switch, and a folder the person added); `allowed` the guarded places the person has said to look in.
    public static func discover(readers: RecordingReaders, saved: [RecordingSourceEntry], allowed: Set<String> = [],
                                definitions: [RecordingSourceDefinition] = RecordingSourceCatalog.definitions) -> [RecordingSource] {
        var found: [RecordingSource] = []
        for definition in definitions where definition.id != RecordingSource.customID {
            let entry = saved.first { $0.id == definition.id }
            if definition.offer == .notOffered {
                guard isPresent(definition, readers) else { continue }
                found.append(RecordingSource(id: definition.id, kind: definition.id, title: definition.title, symbol: definition.symbol,
                                             path: nil, offer: .notOffered, access: .missing, warning: definition.warning, enabled: false))
                continue
            }
            var path: String?
            var access = RecordingSource.Access.missing
            if let resolved = resolve(definition, readers: readers, allowed: allowed) {
                (path, access) = resolved
            } else if let entry {
                path = entry.path
                access = accessOf(entry.path, readers: readers, allowed: allowed)
            }
            guard let path else { continue }
            found.append(RecordingSource(id: definition.id, kind: definition.id, title: definition.title, symbol: definition.symbol,
                                         path: path, offer: definition.offer, access: access, warning: definition.warning,
                                         enabled: entry?.enabled ?? (definition.offer == .on)))
        }
        for entry in saved where entry.isCustom {
            found.append(custom(entry, readers: readers, allowed: allowed))
        }
        return found
    }

    /// A folder the person chose.
    public static func custom(_ entry: RecordingSourceEntry, readers: RecordingReaders, allowed: Set<String> = []) -> RecordingSource {
        RecordingSource(id: entry.key, kind: RecordingSource.customID, title: (entry.path as NSString).lastPathComponent,
                        symbol: RecordingSourceCatalog.definition(RecordingSource.customID)?.symbol ?? "folder",
                        path: entry.path, offer: .on, access: accessOf(entry.path, readers: readers, allowed: allowed),
                        warning: nil, enabled: entry.enabled)
    }

    private static func accessOf(_ path: String, readers: RecordingReaders, allowed: Set<String>) -> RecordingSource.Access {
        if let area = protectedArea(path, home: readers.home), !allowed.contains(area) { return .needsAccess(area) }
        return readers.folderExists(path) ? .readable : .missing
    }

    private static func isPresent(_ definition: RecordingSourceDefinition, _ readers: RecordingReaders) -> Bool {
        definition.findBy.contains { step in
            switch step.kind {
            case .always: true
            case .app(let name): readers.appInstalled(name)
            case .cloudStorage: !readers.cloudMountNames().isEmpty
            default: false
            }
        }
    }

    /// The first step that finds a folder, else the first folder that sits in a guarded place (not looked at).
    private static func resolve(_ definition: RecordingSourceDefinition, readers: RecordingReaders,
                                allowed: Set<String>) -> (String, RecordingSource.Access)? {
        var pending: (String, RecordingSource.Access)?
        for step in definition.findBy {
            if let app = step.onlyWithApp, !readers.appInstalled(app) { continue }
            for candidate in candidates(step.kind, readers) {
                if let area = protectedArea(candidate, home: readers.home), !allowed.contains(area) {
                    if pending == nil { pending = (candidate, .needsAccess(area)) }
                    continue
                }
                if readers.folderExists(candidate) { return (candidate, .readable) }
            }
        }
        return pending
    }

    private static func candidates(_ kind: RecordingSourceDefinition.Step.Kind, _ readers: RecordingReaders) -> [String] {
        let home = readers.home
        func plain(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            if value == "~" { return home }
            if value.hasPrefix("~/") { return home + value.dropFirst(1) }
            return value.hasPrefix("/") ? value : nil
        }
        switch kind {
        case .defaults(let domain, let key, let suffix):
            return plain(readers.defaultsString(domain, key)).map { [$0 + suffix] } ?? []
        case .screencapture:
            let recorded = plain(readers.defaultsString("com.apple.screencapture", "location-screenrecording"))
            let general = plain(readers.defaultsString("com.apple.screencapture", "location"))
            // the first one that is set is THE folder: a guarded place does not make the next one apply
            let chosen = recorded ?? general ?? "\(home)/Desktop"
            return [chosen.hasSuffix("/") ? String(chosen.dropLast()) : chosen]
        case .home(let path): return ["\(home)/\(path)"]
        case .documents(let path): return ["\(home)/Documents/\(path)"]
        case .movies(let path): return ["\(home)/Movies/\(path)"]
        case .app, .cloudStorage, .always: return []
        }
    }
}
