import Foundation

/// What KIND of thing each group is, read from the catalog (`memory-analyzer/rules/kinds.json`). The category
/// is the census's decision and is never changed here; the kind only says what the group is inside it.
extension CensusBuilder {

    /// What the system supplies that the rules ask about, read once per census.
    var kindEnvironment: KindEnvironment {
        if let known = kindEnvironmentMemo { return known }
        let live = KindEnvironment.live()
        kindEnvironmentMemo = live
        return live
    }

    /// One app's bundle identifier and category, from its own Info.plist (one read per bundle).
    func appInfo(at path: String) -> (bundleID: String?, category: String?) {
        if let known = appInfoMemo[path] { return known }
        let info = Bundle(path: path)?.infoDictionary
        let found = (info?["CFBundleIdentifier"] as? String, info?["LSApplicationCategoryType"] as? String)
        appInfoMemo[path] = found
        return found
    }

    /// What the rules are asked about a process.
    func subject(of entry: Entry, command: String?, appName: String? = nil, appPath: String? = nil) -> ProcessSubject {
        let info = appPath.map(appInfo(at:))
        return ProcessSubject(path: entry.path, command: command, uid: entry.uid, me: me, ppid: entry.ppid,
                              bundleID: info?.bundleID, appCategory: info?.category, appName: appName, appPath: appPath)
    }

    /// Whether this process is developer tooling, by its kind: what the guard's old text pattern used to say.
    func isDevTooling(_ entry: Entry, command: String) -> Bool {
        kinds.isDevTooling(subject(of: entry, command: command))
    }

    /// The kind of a group, from the process that stands for it (the top of its biggest tree).
    func kind(ofGroup name: String, category: CensusGroup.Category, appPath: String?, lead: Entry) -> KindMatch {
        var path = appPath
        var bundleID: String?
        var appCategory: String?
        if category == .apps {
            // a helper outside any bundle belongs to an app by identifier only: that app's own record answers
            if path == nil, let owner = appIdentifiers().first(where: { $0.name == name }) {
                path = owner.path
            }
            if let path { (bundleID, appCategory) = appInfo(at: path) }
        }
        let subject = ProcessSubject(path: lead.path, command: argv(lead), uid: lead.uid, me: me, ppid: lead.ppid,
                                     bundleID: bundleID, appCategory: appCategory,
                                     appName: category == .apps ? name : nil, appPath: path)
        return kinds.recognize(subject, in: category, environment: kindEnvironment)
    }

    /// Why a group is left alone, as a sentence: nobody's account but its own can stop another's, and a kind can
    /// carry its own reason (macOS, a live coding session, a Connection Tool).
    func leftAlone(kind: ProcessKind, category: CensusGroup.Category, lead: Entry) -> String? {
        if category != .system, lead.uid != me {
            return "Runs under another account, so no app of yours can stop it."
        }
        return kind.leftAlone
    }
}
