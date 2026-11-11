import Foundation
import os
import Synchronization

/// Which running programs belong to a live AI coding session — read from
/// `lib/coding-agents.tsv`, the ONE list the cleaners' exemption
/// (`lib/live-sessions.sh`) reads too, so the app and the engine can never
/// disagree about what is protected (`agent-runner --probe-agents` fails if
/// they do). The guard-rules blueprint's Coding Agents (adapters as data)
/// extend that file rather than adding another list.
///
/// A HOST is the root of a session (the `claude` process, an agent's language
/// server). Everything that descends from a host belongs to the session.
///
/// An agent that is not in the file is NOT protected: its sessions look like
/// any other developer tooling — there is no way to protect what nobody has named.
///
/// A list that cannot be read, or that names no agent, fails CLOSED: nothing that
/// is not a polite app quit is stopped from the app (`isAvailable`, `unavailableSentence`),
/// and the cleaners refuse to sweep (`lib/live-sessions.sh`). Not knowing which
/// programs belong to a coding session is never read as "none do".
public enum CodingAgentHosts {

    struct Entry: Sendable {
        let agent: String
        let kind: String
        let text: String
        let also: String?
    }

    private static let log = Logger(subsystem: "com.mac-analyzers.app", category: "agents")

    /// The list, read again whenever the file changes (a `git pull` or an update that
    /// changes it takes effect without a relaunch). The file's date is looked at
    /// at most once a second, because every process classified asks for the list.
    static var entries: [Entry] {
        state.withLock { current in
            let now = Date()
            if let loaded = current.entries {
                if now.timeIntervalSince(current.checked) < 1 { return loaded }
                current.checked = now
                if modified(of: current.url) == current.modified { return loaded }
            }
            // the list of the engine the app is using: the checkout, else the bundled copy
            let url = current.override ?? AnalyzersPaths.suiteRoot.appending(path: "lib/coding-agents.tsv")
            let loaded = load(url)
            current.url = url
            current.modified = modified(of: url)
            current.checked = now
            current.entries = loaded
            let agents = Set(loaded.filter { $0.kind != "ignore" }.map(\.agent)).count
            log.info("coding-agents.tsv in use: \(url.path, privacy: .public) (\(agents) agents)")
            return loaded
        }
    }

    private static func modified(of url: URL?) -> Date? {
        url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    }

    private struct State {
        var override: URL?
        var entries: [Entry]?
        var url: URL?
        var modified: Date?
        var checked = Date.distantPast
    }
    private static let state = Mutex(State())

    /// A list file to read instead of the resolved suite's (a checkout that is not
    /// `~/mac-analyzers`, or a fixture list). Test support; it replaces what was read.
    @_spi(TestSupport) public static func useList(at url: URL) {
        state.withLock { $0 = State(override: url) }
    }

    /// The list was found, read and names at least one agent. When it is not,
    /// the app cannot tell which programs belong to a coding session, so it stops none.
    public static var isAvailable: Bool { entries.contains { $0.kind != "ignore" } }

    public static let unavailableSentence =
        "Mac Analyzers can't tell which programs belong to a coding session right now, so it won't stop any."

    static func load(_ url: URL) -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            log.error("coding-agents.tsv not found at \(url.path, privacy: .public): no coding session is protected")
            return []
        }
        // any newline (Windows files end lines with \r\n, which Swift reads as ONE character)
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw)
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }
            return Entry(agent: fields[0], kind: fields[1], text: fields[2],
                         also: fields.count >= 4 && !fields[3].isEmpty ? fields[3] : nil)
        }
    }

    /// The agent a command line is the ROOT of a session for, or nil.
    public static func agent(forCommand command: String) -> String? {
        agent(forCommand: command, in: entries)
    }

    static func agent(forCommand command: String, in list: [Entry]) -> String? {
        let first = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        let executable = first.split(separator: "/").last.map(String.init) ?? first
        if list.contains(where: { $0.kind == "ignore" && $0.text == executable }) { return nil }
        for entry in list {
            switch entry.kind {
            case "exe" where entry.text == executable:
                return entry.agent
            case "fragment" where command.contains(entry.text):
                if let also = entry.also, !command.contains(also) { continue }
                return entry.agent
            default:
                continue
            }
        }
        return nil
    }

    /// The probe's way in: the same matching, against a list file it names (a
    /// checkout other than the one the app resolves), and the agents in it.
    @_spi(TestSupport) public static func probe(listAt url: URL) -> (agentNames: [String], classify: (String) -> String?) {
        let list = load(url)
        return (Array(Set(list.filter { $0.kind != "ignore" }.map(\.agent))).sorted(),
                { agent(forCommand: $0, in: list) })
    }

    /// Every agent named in the list, for the probe.
    public static var agentNames: [String] {
        Array(Set(entries.filter { $0.kind != "ignore" }.map(\.agent))).sorted()
    }

    /// For each process, the agent whose session it belongs to — the process
    /// itself when it is a root, or the nearest ancestor that is. Processes
    /// outside any session are absent.
    public static func sessionOwners(among table: [Int: (command: String, ppid: Int)]) -> [Int: String] {
        var roots: [Int: String] = [:]
        for (pid, entry) in table {
            if let agent = agent(forCommand: entry.command) { roots[pid] = agent }
        }
        var owners: [Int: String] = [:]
        for pid in table.keys {
            var current = pid
            var hops = 0
            while hops < 40 {
                if let agent = roots[current] { owners[pid] = agent; break }
                guard let parent = table[current]?.ppid, parent > 1, parent != current else { break }
                current = parent
                hops += 1
            }
        }
        return owners
    }

    /// The agent whose live session this one process belongs to, read from the
    /// process table as it is now: itself or any ancestor. Used at the moment
    /// of a stop, by anything that is about to signal a single pid.
    public static func liveSessionAgent(pid: Int) -> String? {
        var current = Int32(pid)
        var hops = 0
        while current > 1, hops < 40 {
            let command = ProcTable.commandLine(of: current)
            let path = ProcTable.executablePath(of: current)
            if let agent = agent(forCommand: command.isEmpty ? path : command)
                ?? agent(forCommand: path) { return agent }
            let parent = ProcTable.parentPID(of: current)
            guard parent > 1, Int32(parent) != current else { break }
            current = Int32(parent)
            hops += 1
        }
        return nil
    }

    /// The live coding sessions that run BELOW this process, anywhere in its whole
    /// subtree (through shells and everything else): agent → how many session roots.
    /// A process that hosts terminals (a terminal's server, `tmux`, `screen`) ends
    /// every session inside them when it ends.
    public static func sessionsBelow(pid: Int) -> [String: Int] {
        var children: [Int32: [Int32]] = [:]
        for other in ProcTable.allPIDs() { children[Int32(ProcTable.parentPID(of: other)), default: []].append(other) }
        return sessionsBelow(roots: [Int32(pid)], children: children)
    }

    /// The same over a child map already built, for a caller that has one.
    static func sessionsBelow(roots: [Int32], children: [Int32: [Int32]]) -> [String: Int] {
        var found: [String: Int] = [:]
        var seen = Set<Int32>()
        var stack = roots
        while let pid = stack.popLast() {
            guard seen.insert(pid).inserted else { continue }
            if !roots.contains(pid) {
                let command = ProcTable.commandLine(of: pid)
                let path = ProcTable.executablePath(of: pid)
                if let agent = agent(forCommand: command.isEmpty ? path : command) ?? agent(forCommand: path) {
                    found[agent, default: 0] += 1
                }
            }
            stack.append(contentsOf: children[pid] ?? [])
        }
        return found
    }
}
