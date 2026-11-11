import Foundation

/// One entry of the startup-changes history: something was added to the
/// places software starts itself from, or the app first took stock of them.
/// Built from `persistence.log`, which the persistence watcher appends to.
public struct StartupChange: Identifiable, Hashable, Sendable {

    public enum Event: Sendable, Hashable {
        /// A launch agent or daemon appeared.
        case added
        /// The first look: how many items were there to begin with.
        case firstLook(count: Int)
    }

    public let id: String
    public let date: Date
    public let event: Event
    /// The plist that appeared; nil for the first look.
    public let path: String?
    /// What it is called and who it belongs to, from its file name.
    public let name: String
    public let owner: String

    /// "Added to Launch Daemons" and so on.
    public var title: String {
        switch event {
        case .added: "\(name) was added"
        case .firstLook(let count): "Startup items first recorded (\(count))"
        }
    }

    /// Where it was added, in words.
    public var place: String {
        guard let path else { return "" }
        if path.contains("/LaunchDaemons/") { return "Launch Daemons" }
        if path.hasPrefix(AnalyzersPaths.home.path) { return "Your Launch Agents" }
        return "Launch Agents for all users"
    }

    /// The one-line outcome: who it belongs to and where it went.
    public var detail: String {
        switch event {
        case .added: "\(owner) · \(place)"
        case .firstLook: "From here on, anything new is listed."
        }
    }

    /// True while the plist is still on disk.
    public var stillInstalled: Bool {
        path.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }

    /// The inventory row for this change, when the audit has seen it.
    public func item(in inventory: StartupInventory?) -> StartupItem? {
        guard let path else { return nil }
        return inventory?.items.first { $0.plistPath == path }
    }
}

public enum StartupChangeParser {

    /// Newest first. `limit` keeps a very old log from costing a screen.
    public static func read(at url: URL = AnalyzersPaths.persistenceLog, limit: Int = 500) -> [StartupChange] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, limit: limit)
    }

    public static func parse(_ text: String, limit: Int = 500) -> [StartupChange] {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var changes: [StartupChange] = []
        var ordinals: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            guard line.count > 20, let date = stamp.date(from: String(line.prefix(19))) else { continue }
            let rest = line.dropFirst(20)
            let event: StartupChange.Event
            var path: String?
            if rest.hasPrefix("NEW persistence item: ") {
                event = .added
                path = String(rest.dropFirst("NEW persistence item: ".count))
            } else if rest.hasPrefix("BASELINE seeded") {
                let digits = rest.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 0
                event = .firstLook(count: digits)
            } else {
                continue
            }
            let key = String(line)
            let n = ordinals[key, default: 0]
            ordinals[key] = n + 1

            let file = path.map { ($0 as NSString).lastPathComponent } ?? ""
            let label = (file as NSString).deletingPathExtension
            let owner = path == nil ? "" : StartupNaming.vendor(ofLabel: label)
            let name = path == nil ? "" : StartupNaming.itemName(ofLabel: label, owner: owner)
            changes.append(StartupChange(id: "\(key)#\(n)", date: date, event: event,
                                         path: path, name: name, owner: owner))
        }
        return Array(changes.reversed().prefix(limit))
    }
}
