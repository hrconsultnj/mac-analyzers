import Foundation
import os

/// What the last login-items audit looked at: every startup item with the
/// audit's own verdict. Read from `login-items.tsv`, which the script writes
/// next to its log on every run (columns in the script's header). Nothing
/// here re-decides a verdict.
public struct StartupInventory: Sendable {
    public let items: [StartupItem]
    /// When the audit that wrote it ran.
    public let ranAt: Date?
    /// The run's own identifier, exactly as its log banner prints it (`(run
    /// 4242-17)`; two runs can start in the same second): how an inventory is
    /// tied to the audit job that wrote it.
    public let stamp: String
    /// True when that audit only looked (the default); false when it removed.
    public let wasDryRun: Bool
    /// True when the audit that wrote it could NOT list the System Settings login items (System Events was not
    /// scriptable): the file then says nothing about which apps open at login. Read from the header's `logins=` field.
    public var loginItemsUnreadable = false

    /// What the screen says over the Apps tab in that case.
    public static let loginItemsUnreadableSentence = "Your Login Items could not be read, so apps that open at login are not listed. Run the audit from Mac Analyzers (Audit), where macOS can ask for permission. If it was refused, turn it on in System Settings, under Privacy & Security, Automation."

    public var leftovers: [StartupItem] { items.filter { $0.finding == .leftover || $0.finding == .possibleLeftover } }
    /// What the app can offer to remove: user-level leftovers (the script
    /// re-checks each one against what it finds when the removal runs).
    public var removable: [StartupItem] { items.filter(\.canRemove) }

    /// True when this inventory was written by the audit run that printed
    /// `lines`: the run's stamp is in its own banner. An inventory from any other
    /// run (the Terminal, another audit) is not the list a removal was built from.
    public func isFromRun(printing lines: [String]) -> Bool {
        !stamp.isEmpty && lines.contains { $0.contains(stamp) }
    }

    // MARK: - levels: category (tab) > group (the app or developer) > item

    public func items(in category: StartupItem.Category) -> [StartupItem] {
        items.filter { $0.category == category }
    }

    /// Groups in a category: one per app or developer, largest first. An app
    /// with five helpers is one group.
    public func groups(in category: StartupItem.Category,
                       matching filter: (StartupItem) -> Bool = { _ in true }) -> [StartupGroup] {
        let members = items(in: category).filter(filter)
        let canonical = canonicalOwners()
        return Dictionary(grouping: members, by: { canonical[$0.owner] ?? $0.owner })
            .map { StartupGroup(category: category, name: $0.key,
                                items: $0.value.sorted { ($0.finding.rank, $0.name) < ($1.finding.rank, $1.name) }) }
            .sorted { ($0.items.count, $1.name) > ($1.items.count, $0.name) }
    }

    /// One name per developer (see `StartupNaming.canonicalNames`).
    func canonicalOwners() -> [String: String] { StartupNaming.canonicalNames(items.map(\.owner)) }

    /// Problems with the shape of the levels: one catch-all category, or a
    /// title that repeats inside a group. The probe fails on any.
    public func levelProblems() -> [String] {
        var problems: [String] = []
        let counts = StartupItem.Category.allCases.map { items(in: $0).count }
        if items.count >= 6, counts.contains(items.count) {
            problems.append("one category holds all \(items.count) items")
        }
        for category in StartupItem.Category.allCases {
            for group in groups(in: category) {
                let titles = group.items.map(\.name)
                for title in Set(titles) where titles.filter({ $0 == title }).count > 1 {
                    problems.append("\(category.title) › \(group.name): \"\(title)\" appears more than once")
                }
            }
        }
        return problems
    }

    public static let fileName = "login-items.tsv"

    private static let override = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// Test hook: read this file instead of the real one, so SnapshotRunner can
    /// show a screen from a fixture without touching the reports folder. Only
    /// the targets that may import the test interface can call it.
    @_spi(TestSupport) public static func useFile(_ url: URL?) { override.withLock { $0 = url } }

    public static var file: URL {
        override.withLock { $0 } ?? AnalyzersPaths.storageReports.appending(path: fileName)
    }

    /// The newest inventory, or nil when no audit has written one yet.
    public static func latest(at url: URL = file) -> StartupInventory? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public static func parse(_ text: String) -> StartupInventory? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first, header.hasPrefix("#login-items-inventory") else { return nil }
        let head = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let ranAt = head.count > 2 ? stamp.date(from: head[2]) : nil
        let dryRun = head.count > 3 ? head[3] == "dry-run" : true

        var items: [StartupItem] = []
        var seen: Set<String> = []
        for line in lines.dropFirst() {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 8, let kind = StartupItem.Kind(token: f[0]) else { continue }
            let scope: StartupItem.Scope = f[1] == "system" ? .system : .user
            let plist = f[3].isEmpty ? nil : f[3]
            let target = f[4].isEmpty ? nil : f[4]
            var id = "\(kind.rawValue)|\(scope.rawValue)|\(plist ?? f[2])"
            if !seen.insert(id).inserted { id += "|\(target ?? "")" }
            let who = StartupNaming.identify(kind: kind, label: f[2], target: target)
            items.append(StartupItem(
                id: id, kind: kind, scope: scope, label: f[2],
                plistPath: plist, targetPath: target,
                finding: .init(token: f[5]), state: .init(token: f[6]),
                reason: StartupItem.Reason(rawValue: f[7]) ?? .none,
                fixCommand: f.count > 8 && !f[8].isEmpty ? f[8] : nil,
                name: who.name, owner: who.owner, ownerSource: who.ownerSource,
                ownerNote: who.ownerNote, appPath: who.appPath))
        }
        return StartupInventory(items: disambiguated(items), ranAt: ranAt,
                                stamp: head.count > 4 ? "(run \(head[4]))" : (head.count > 2 ? head[2] : ""),
                                wasDryRun: dryRun,
                                loginItemsUnreadable: head.count > 5 && head[5] == "logins=unreadable")
    }

    /// Two items of one app can share a name (the same agent in your folder and
    /// in the all-users folder). Tell them apart by where they live.
    static func disambiguated(_ items: [StartupItem]) -> [StartupItem] {
        var seen: [String: Int] = [:]
        for item in items { seen["\(item.category.rawValue)|\(item.owner)|\(item.name)", default: 0] += 1 }
        return items.map { item in
            guard seen["\(item.category.rawValue)|\(item.owner)|\(item.name)", default: 0] > 1 else { return item }
            return item.renamed("\(item.name) (\(item.scope == .user ? "yours" : "all users"))")
        }
    }
}
