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
    /// Whether a folder is a link, and where it really leads. Never called for a place macOS asks permission for,
    /// until the person has clicked.
    public var linkInfo: @Sendable (_ path: String) -> (isLink: Bool, resolved: String)?

    public init(home: String,
                defaultsString: @escaping @Sendable (String, String) -> String?,
                folderExists: @escaping @Sendable (String) -> Bool,
                appInstalled: @escaping @Sendable (String) -> Bool,
                cloudMountNames: @escaping @Sendable () -> [String],
                linkInfo: @escaping @Sendable (String) -> (isLink: Bool, resolved: String)? = { _ in nil }) {
        self.linkInfo = linkInfo
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
            },
            linkInfo: { path in
                guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
                let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
                return (isLink, URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
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

    /// The guarded place a path is in, or nil: `Documents`, `Desktop`, `Downloads`, `iCloud Drive` and `External Disks`
    /// are the places macOS can ask the person about when a program looks inside.
    public static func protectedArea(_ path: String, home: String) -> String? {
        for area in ["Documents", "Desktop", "Downloads"] {
            let root = "\(home)/\(area)"
            if path == root || path.hasPrefix(root + "/") { return area }
        }
        let icloud = "\(home)/Library/Mobile Documents"
        if path == icloud || path.hasPrefix(icloud + "/") { return "iCloud Drive" }
        if path.hasPrefix("/Volumes/") { return "External Disks" }
        return nil
    }

    /// Whether this folder can be a source at all. A folder in a guarded place is judged from its name alone until the
    /// person has said to look there; any other is also checked for links, which needs no permission.
    public static func refusal(_ path: String, layout: RecordingSourceDefinition.Layout, readers: RecordingReaders,
                               allowed: Set<String>) -> String? {
        var isLink = false
        var resolved: String?
        if protectedArea(path, home: readers.home).map({ allowed.contains($0) }) ?? true, let info = readers.linkInfo(path) {
            isLink = info.isLink
            resolved = info.resolved
        }
        return RecordingFolderRule.refusal(path, layout: layout, home: readers.home,
                                           homeResolved: URL(fileURLWithPath: readers.home).resolvingSymlinksInPath().path,
                                           isLink: isLink, resolved: resolved)
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
            if let why = refusal(path, layout: definition.layout, readers: readers, allowed: allowed) { access = .refused(why) }
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
        var access = accessOf(entry.path, readers: readers, allowed: allowed)
        if let why = refusal(entry.path, layout: .folders, readers: readers, allowed: allowed) { access = .refused(why) }
        return RecordingSource(id: entry.key, kind: RecordingSource.customID, title: (entry.path as NSString).lastPathComponent,
                        symbol: RecordingSourceCatalog.definition(RecordingSource.customID)?.symbol ?? "folder",
                        path: entry.path, offer: .on, access: access, warning: nil, enabled: entry.enabled)
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
