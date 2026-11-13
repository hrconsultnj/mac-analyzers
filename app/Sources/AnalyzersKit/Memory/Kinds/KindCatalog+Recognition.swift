import Foundation

/// What the system supplies that the rules ask about, gathered once per census (or handed in by a probe).
public struct KindEnvironment: Sendable {
    /// Bundle identifiers (lowercased) and paths of the apps that open web links.
    public let httpsHandlers: Set<String>
    /// Executable path → the label of the launchd job that keeps it running.
    public let launchdPrograms: [String: String]

    public init(httpsHandlers: Set<String>, launchdPrograms: [String: String]) {
        self.httpsHandlers = httpsHandlers
        self.launchdPrograms = launchdPrograms
    }

    /// Nothing known: for a caller that has only a command line.
    public static let none = KindEnvironment(httpsHandlers: [], launchdPrograms: [:])

    /// Read from the system, for a census.
    public static func live() -> KindEnvironment {
        KindEnvironment(httpsHandlers: BrowserHandlers.current(), launchdPrograms: LaunchdServices.programs())
    }
}

/// Matching a process to a kind. First match wins, in four passes: the identity rules of the specific kinds,
/// then their name rules (nothing better exists for those), then the generic kinds in the file's order (a JavaScript
/// runtime, then a tool server found by its name), then
/// the category's fallback. Within a pass the file's order decides. A process is only ever matched against the
/// kinds of the category the census gave it, so a kind can never move a process to another category.
extension KindCatalog {

    public func recognize(_ subject: ProcessSubject, in category: CensusGroup.Category,
                          environment: KindEnvironment = .none) -> KindMatch {
        guard isAvailable else {
            return KindMatch(kind: fallbackKind(for: category), basis: .fallback, rule: "the list of kinds could not be read")
        }
        let facts = Facts(subject, environment: environment)
        let candidates = entries.filter { $0.kind.category == category && !$0.fallback }
        let specific = candidates.filter { !$0.generic }
        // a nil basis takes a rule of either kind (the generic kinds, identity first by their own order)
        let passes: [(entries: [Entry], basis: KindMatch.Basis?)] = [
            (specific, .identity), (specific, .name), (candidates.filter(\.generic), nil),
        ]
        for pass in passes {
            for entry in pass.entries {
                for rule in entry.rules where pass.basis == nil || rule.by.basis == pass.basis {
                    if let words = facts.match(rule) {
                        return KindMatch(kind: entry.kind, basis: rule.by.basis, rule: "\(rule.by.rawValue) \(words)")
                    }
                }
            }
        }
        return KindMatch(kind: fallbackKind(for: category), basis: .fallback, rule: "no rule matched")
    }

    /// Whether a program is developer tooling: what the guard's old pattern selected. For a caller that has a
    /// command line and nothing else (the live process lists).
    public func isDevTooling(command: String) -> Bool {
        isDevTooling(ProcessSubject(path: command.split(separator: " ").first.map(String.init) ?? command, command: command,
                                    uid: 0, me: 0))
    }

    public func isDevTooling(_ subject: ProcessSubject, environment: KindEnvironment = .none) -> Bool {
        recognize(subject, in: .tools, environment: environment).kind.devTooling
    }

    /// The facts one process offers the rules, worked out once.
    private struct Facts {
        let subject: ProcessSubject
        let environment: KindEnvironment
        /// File names the program goes by: its path's, its first word's.
        let executables: Set<String>
        /// The script an interpreter was asked to run, without its extension.
        let script: String?
        /// The command line cut into words; a whole word is what a name rule matches.
        let tokens: [String]
        let paths: [String]

        init(_ subject: ProcessSubject, environment: KindEnvironment) {
            self.subject = subject
            self.environment = environment
            let words = subject.command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let first = words.first ?? ""
            var names = Set<String>()
            if !first.isEmpty { names.insert(Self.fileName(first)) }
            if !subject.path.hasPrefix("pid ") { names.insert(Self.fileName(subject.path)) }
            executables = names
            let interpreters = Set(CodingAgentHosts.entries.filter { $0.kind == "interpreter" }.map(\.text))
            if interpreters.contains(Self.fileName(first)),
               let word = words.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                script = Self.withoutExtension(Self.fileName(word))
            } else {
                script = nil
            }
            tokens = subject.command.split(whereSeparator: { " /=:@".contains($0) }).map(String.init)
            paths = [subject.path, first]
        }

        static func fileName(_ path: String) -> String {
            let base = path.split(separator: "/").last.map(String.init) ?? path
            return base.hasPrefix("-") ? String(base.dropFirst()) : base
        }

        static func withoutExtension(_ name: String) -> String {
            for ending in [".js", ".mjs", ".cjs", ".ts"] where name.hasSuffix(ending) { return String(name.dropLast(ending.count)) }
            return name
        }

        /// A whole word, or a run of words, of the command line. A single word also matches a part of a longer
        /// hyphenated, underscored or dotted word (`mcp` in `mcp-server-files`), never a part of a plain one.
        func hasWords(_ value: String) -> Bool {
            let wanted = value.split(separator: " ").map(String.init)
            if wanted.count > 1 {
                return tokens.indices.contains { start in
                    start + wanted.count <= tokens.count && Array(tokens[start..<start + wanted.count]) == wanted
                }
            }
            if tokens.contains(value) { return true }
            guard !value.contains("-"), !value.hasPrefix("-") else { return false }
            return tokens.contains { $0.split(whereSeparator: { "-_.".contains($0) }).contains { String($0) == value } }
        }

        /// What matched, in words, or nil.
        func match(_ rule: Rule) -> String? {
            switch rule.by {
            case .agentRoot:
                let line = subject.command.isEmpty ? subject.path : subject.command
                return CodingAgentHosts.agent(forCommand: line).map { "session root of \($0)" }
            case .bundleId:
                guard let id = subject.bundleID?.lowercased() else { return nil }
                return rule.values.first { id == $0.lowercased() || id.hasPrefix($0.lowercased() + ".") }
            case .appCategory:
                return subject.appCategory.flatMap { category in rule.values.first { $0 == category } }
            case .httpsHandler:
                let known = subject.bundleID.map { environment.httpsHandlers.contains($0.lowercased()) } == true
                    || subject.appPath.map { environment.httpsHandlers.contains($0) } == true
                return known ? "opens web links" : nil
            case .containerApp:
                return subject.appName.flatMap { CodingAgentHosts.isContainerRuntime(appName: $0) ? "listed container app \($0)" : nil }
            case .exe:
                return rule.values.first { executables.contains($0) }
            case .exePath:
                return rule.values.first { value in paths.contains { $0.contains(value) } }
            case .script:
                return script.flatMap { name in rule.values.first { $0 == name } }
            case .launchdLabel:
                guard subject.ppid == 1, let label = environment.launchdPrograms[subject.path] else { return nil }
                return label
            case .otherAccount:
                return subject.uid != subject.me ? "runs as another account" : nil
            case .argv:
                return rule.values.first(where: hasWords)
            }
        }
    }
}
