import Foundation
import os
import Synchronization

/// The kinds of process, read from `memory-analyzer/rules/kinds.json` (bundled with the engine, updated with the app).
///
/// This file is the loading and the checking. How a process is matched to a kind is in
/// `KindCatalog+Recognition.swift`; what the system supplies that the rules ask about (the apps that open web
/// links, the programs launchd keeps running) is in `BrowserHandlers.swift` and `LaunchdServices.swift`.
///
/// A catalog that cannot be read, or that breaks one of its own rules (an unknown field, a rule that rests on a
/// name without saying why, a category with no fallback kind), is NOT used in part: every process then reads as
/// the category's "unclassified" kind, which allows the guard nothing. Not knowing what something is is never read
/// as "it is safe to stop".
public final class KindCatalog: Sendable {

    enum By: String, CaseIterable {
        case agentRoot, bundleId, appCategory, httpsHandler, containerApp
        case exe, exePath, script, launchdLabel, otherAccount, argv

        /// What the rule rests on. Fixed here, and the file must say the same, so a rule cannot claim an identity it does not have.
        var basis: KindMatch.Basis {
            switch self {
            case .containerApp, .argv: .name
            default: .identity
            }
        }

        /// Whether the rule lists values (a bundle identifier, an executable name) or asks the system.
        var takesValues: Bool {
            switch self {
            case .agentRoot, .httpsHandler, .containerApp, .launchdLabel, .otherAccount: false
            default: true
            }
        }
    }

    struct Rule: Sendable {
        let by: By
        let values: [String]
    }

    struct Entry: Sendable {
        let kind: ProcessKind
        let rules: [Rule]
        /// Matched only after every specific kind has had its turn (a JavaScript runtime).
        let generic: Bool
        /// The category's "other": what is left when no rule matched.
        let fallback: Bool
        /// Required when a rule goes by a name.
        let nameOnlyBecause: String?
    }

    private static let log = Logger(subsystem: "com.mac-analyzers.app", category: "kinds")

    let entries: [Entry]
    /// What is wrong with the file; empty when it can be used.
    public let problems: [String]
    /// The file the catalog was read from.
    public let source: URL?

    public var isAvailable: Bool { problems.isEmpty && !entries.isEmpty }
    public var kinds: [ProcessKind] { entries.map(\.kind) }

    /// A kind that says it rests on a name, with the reason.
    public func nameOnlyReason(of kind: ProcessKind) -> String? {
        entries.first { $0.kind == kind }?.nameOnlyBecause
    }

    public func kind(id: String) -> ProcessKind? { entries.first { $0.kind.id == id }?.kind }

    /// What every process reads as when the catalog is not usable: a kind that lets the guard do nothing.
    public func fallbackKind(for category: CensusGroup.Category) -> ProcessKind {
        if let entry = entries.first(where: { $0.fallback && $0.kind.category == category }) { return entry.kind }
        return ProcessKind(id: "\(Self.prefix(of: category)).unclassified", category: category, devTooling: false,
                           stopsWith: .none, forceAfterGrace: nil,
                           guardMay: "Nothing: the list of kinds could not be read.", leftAlone: nil)
    }

    // MARK: - reading

    private init(entries: [Entry], problems: [String], source: URL?) {
        self.entries = entries
        self.problems = problems
        self.source = source
    }

    static func prefix(of category: CensusGroup.Category) -> String {
        switch category {
        case .apps: "apps"
        case .tools: "tools"
        case .system: "macos"
        }
    }

    /// Reads and checks a catalog. Any problem makes the whole catalog unusable (see the type's note).
    public static func parse(_ data: Data, source: URL? = nil) -> KindCatalog {
        var problems: [String] = []
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return KindCatalog(entries: [], problems: ["not a JSON object"], source: source)
        }
        problems += unknownKeys(in: root, allowed: ["schema", "about", "kinds"], at: "the file")
        if root["schema"] as? Int != 1 { problems.append("schema is not 1") }
        guard let raw = root["kinds"] as? [[String: Any]] else {
            return KindCatalog(entries: [], problems: problems + ["no kinds list"], source: source)
        }

        var entries: [Entry] = []
        for item in raw {
            let id = item["id"] as? String ?? "(no id)"
            let before = problems.count
            problems += unknownKeys(in: item, allowed: ["id", "category", "devTooling", "stopsWith", "forceAfterGrace",
                                                        "guardMay", "leftAlone", "nameOnlyBecause", "generic", "fallback",
                                                        "recognizedBy"], at: id)
            guard let category = categoryOf(item["category"] as? String) else { problems.append("\(id): unknown category"); continue }
            guard id.hasPrefix(prefix(of: category) + ".") else { problems.append("\(id): id does not start with \(prefix(of: category))."); continue }
            guard let stops = (item["stopsWith"] as? String).flatMap(ProcessKind.StopsWith.init(rawValue:)) else {
                problems.append("\(id): stopsWith must be quit, stop or none"); continue
            }
            guard let guardMay = item["guardMay"] as? String, !guardMay.isEmpty else { problems.append("\(id): no guardMay sentence"); continue }
            let devTooling = item["devTooling"] as? Bool ?? false
            if devTooling, category != .tools { problems.append("\(id): only tools can be developer tooling") }
            let grace = item["forceAfterGrace"] as? Int
            if grace != nil, !devTooling { problems.append("\(id): only developer tooling may be forced") }
            var rules: [Rule] = []
            var namesWords = false
            for (index, rule) in ((item["recognizedBy"] as? [[String: Any]]) ?? []).enumerated() {
                let label = "\(id) rule \(index + 1)"
                problems += unknownKeys(in: rule, allowed: ["by", "basis", "values"], at: label)
                guard let by = (rule["by"] as? String).flatMap(By.init(rawValue:)) else { problems.append("\(label): unknown kind of rule"); continue }
                if rule["basis"] as? String != by.basis.rawValue { problems.append("\(label): \(by.rawValue) rests on \(by.basis.rawValue)") }
                let values = rule["values"] as? [String] ?? []
                if by.takesValues == values.isEmpty { problems.append("\(label): \(by.rawValue) \(by.takesValues ? "needs values" : "takes none")") }
                if by.basis == .name { namesWords = true }
                rules.append(Rule(by: by, values: values))
            }
            let fallback = item["fallback"] as? Bool ?? false
            if fallback, !rules.isEmpty { problems.append("\(id): a fallback kind has no rules") }
            if namesWords, (item["nameOnlyBecause"] as? String ?? "").isEmpty { problems.append("\(id): a rule goes by a name and the kind does not say why") }
            if Names.Kind.name(forID: id) == nil { problems.append("\(id): no name in Names.Kind") }
            guard problems.count == before else { continue }
            entries.append(Entry(
                kind: ProcessKind(id: id, category: category, devTooling: devTooling, stopsWith: stops, forceAfterGrace: grace,
                                  guardMay: guardMay, leftAlone: item["leftAlone"] as? String),
                rules: rules, generic: item["generic"] as? Bool ?? false, fallback: fallback,
                nameOnlyBecause: item["nameOnlyBecause"] as? String))
        }

        for category in CensusGroup.Category.allCases {
            let inCategory = entries.filter { $0.kind.category == category }
            if inCategory.filter(\.fallback).count != 1 { problems.append("\(prefix(of: category)): needs exactly one fallback kind") }
            else if inCategory.last?.fallback != true { problems.append("\(prefix(of: category)): the fallback kind must come last") }
        }
        if Set(entries.map(\.kind.id)).count != entries.count { problems.append("two kinds share an id") }
        return problems.isEmpty ? KindCatalog(entries: entries, problems: [], source: source)
            : KindCatalog(entries: [], problems: problems, source: source)
    }

    private static func categoryOf(_ name: String?) -> CensusGroup.Category? { name.flatMap(CensusGroup.Category.init(rawValue:)) }

    private static func unknownKeys(in object: [String: Any], allowed: Set<String>, at place: String) -> [String] {
        object.keys.filter { !allowed.contains($0) }.sorted().map { "\(place): unknown field \($0)" }
    }

    // MARK: - the catalog in use

    private struct State {
        var override: URL?
        var catalog: KindCatalog?
        var modified: Date?
        var checked = Date.distantPast
    }
    private static let state = Mutex(State())

    /// The catalog of the engine the app is using (the checkout, else the bundled copy), read again when the file changes.
    /// Its date is looked at once a second at most, because every process classified asks for it.
    public static var current: KindCatalog {
        state.withLock { current in
            let now = Date()
            let url = current.override ?? defaultFile
            if let loaded = current.catalog, loaded.source == url {
                if now.timeIntervalSince(current.checked) < 1 { return loaded }
                current.checked = now
                if modified(of: url) == current.modified { return loaded }
            }
            let data = try? Data(contentsOf: url)
            let loaded = data.map { parse($0, source: url) }
                ?? KindCatalog(entries: [], problems: ["not found at \(url.path)"], source: url)
            current.catalog = loaded
            current.modified = modified(of: url)
            current.checked = now
            if loaded.isAvailable {
                log.info("kinds.json in use: \(url.path, privacy: .public) (\(loaded.entries.count) kinds)")
            } else {
                log.error("kinds.json unusable, every process reads as unclassified: \(loaded.problems.joined(separator: "; "), privacy: .public)")
            }
            return loaded
        }
    }

    /// The checkout's file, else the copy bundled in the app: a clone older than this app (it has no `rules/` yet)
    /// must not leave every process unclassified.
    private static var defaultFile: URL {
        let checkout = AnalyzersPaths.suiteRoot.appending(path: "memory-analyzer/rules/kinds.json")
        if FileManager.default.fileExists(atPath: checkout.path) { return checkout }
        let bundled = Bundle.main.resourceURL?.appending(path: "engine/memory-analyzer/rules/kinds.json")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return checkout
    }

    private static func modified(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// A catalog file to read instead of the resolved suite's (the checkout a probe was built from, or a fixture).
    /// Test support; it replaces what was read.
    @_spi(TestSupport) public static func use(file url: URL) {
        state.withLock { $0 = State(override: url) }
    }
}
