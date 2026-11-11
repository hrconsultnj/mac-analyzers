import Foundation

/// A tools group's separate programs: who each one is, where it runs, and
/// whether a live coding session owns it.
extension CensusBuilder {

    func programs(rootMembers: [Int: [LiveProcess]], sessions: inout SessionLookup) -> [StopTarget] {
        // the live children of every process, for the whole-subtree session check
        var kids: [Int32: [Int32]] = [:]
        for entry in table.values { kids[Int32(entry.ppid), default: []].append(Int32(entry.pid)) }
        return rootMembers.compactMap { rootPid, members -> StopTarget? in
            guard let root = table[rootPid] else { return nil }
            let sorted = members.sorted {
                $0.memoryBytes != $1.memoryBytes ? $0.memoryBytes > $1.memoryBytes : $0.pid < $1.pid
            }
            let identity = ProcessIdentity.of(pid: rootPid)
            let rootProcess = members.first { $0.pid == rootPid } ?? sorted[0]
            let id = identity.map { "program-\($0.pid)-\($0.birth.seconds)-\($0.birth.microseconds)" }
                ?? "program-\(rootPid)"
            // locked when a live session started it, or sits above it
            let locked = sessions.agent(of: rootPid)
            // ... or when a session lives anywhere BELOW it, through shells and
            // everything else: ending a program that hosts terminals ends every
            // session in them
            let hosted = CodingAgentHosts.sessionsBelow(roots: [Int32(rootPid)], children: kids)
            return StopTarget(id: id, identity: identity, name: rootProcess.friendlyName,
                              whereItRuns: whereItRuns(root), lockedBy: locked,
                              canStop: root.uid == me && rootProcess.canQuit, members: sorted,
                              memberIdentities: leafFirst(sorted, root: rootPid),
                              isInteractiveShell: ProgramReach.isInteractiveShell(command: argv(root) ?? root.path),
                              hostedSessions: hosted)
        }
        .sorted { $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.id < $1.id }
    }

    /// Members with their start times, the deepest first, so a stop reaches a
    /// child before the process that started it.
    private func leafFirst(_ members: [LiveProcess], root: Int) -> [ProcessIdentity] {
        let pids = Set(members.map(\.pid))
        var depth: [Int: Int] = [:]
        for member in members {
            var current = member.pid
            var hops = 0
            while current != root, let parent = table[current]?.ppid, pids.contains(parent), hops < 40 {
                current = parent
                hops += 1
            }
            depth[member.pid] = hops
        }
        return members
            .sorted { (depth[$0.pid] ?? 0) > (depth[$1.pid] ?? 0) }
            .compactMap { ProcessIdentity.of(pid: $0.pid) }
    }

    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh"]

    static func isShell(_ entry: Entry, command: String?) -> Bool {
        let first = (command ?? entry.path).split(separator: " ").first.map(String.init) ?? entry.path
        let name = (first.split(separator: "/").last.map(String.init) ?? first).drop { $0 == "-" }
        return shells.contains(String(name))
    }

    /// The project the program's working folder belongs to, else the one its
    /// command line names; nil when neither says.
    private func whereItRuns(_ entry: Entry) -> String? {
        if entry.uid == me, let folder = ProcTable.workingDirectory(of: Int32(entry.pid)),
           let project = ProcessNaming.projectName(forPath: folder) {
            return project
        }
        return argv(entry).flatMap(ProcessNaming.project(inCommand:))
    }
}

/// Which coding-agent session, if any, a process belongs to: its own command
/// line or any ancestor's, all the way up — through shells too, because a dev
/// server a session started sits under the `zsh` the agent opened. Remembers
/// each answer for the one census it serves.
struct SessionLookup {
    private let builder: CensusBuilder
    private var memo: [Int: String?] = [:]

    init(builder: CensusBuilder) { self.builder = builder }

    /// Whether this one process IS a session's root, whatever its ancestors are.
    func ownAgent(of pid: Int) -> String? {
        guard let entry = builder.table[pid] else { return nil }
        return CodingAgentHosts.agent(forCommand: builder.argv(entry) ?? entry.path)
    }

    mutating func agent(of pid: Int) -> String? {
        var chain: [Int] = []
        var current = pid
        var found: String?
        var hops = 0
        while hops < 40 {
            if let known = memo[current] { found = known; break }
            guard let entry = builder.table[current] else { break }
            chain.append(current)
            if let agent = CodingAgentHosts.agent(forCommand: builder.argv(entry) ?? entry.path) {
                found = agent
                break
            }
            guard entry.ppid > 1, entry.ppid != current else { break }
            current = entry.ppid
            hops += 1
        }
        for visited in chain { memo[visited] = .some(found) }
        return found
    }
}
