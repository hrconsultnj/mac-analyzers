import Foundation

/// Fold every process into its owner's group, and each group into parts.
extension CensusBuilder {

    /// Everything gathered for one group while the table is walked.
    private struct Bucket {
        let category: CensusGroup.Category
        let name: String
        var members: [LiveProcess] = []
        /// What each member does — keyed by pid.
        var roles: [Int: ProcessRole.Described] = [:]
        /// Memory under each top-level process — picks the lead, and its
        /// keys are the pids a group-level Quit is sent to.
        var rootTotals: [Int: Int64] = [:]
        /// Top-level processes this user is allowed to quit.
        var quittableRoots: Set<Int> = []
        /// What each top-level process owns — its program.
        var rootMembers: [Int: [LiveProcess]] = [:]
    }

    /// Largest first.
    func groups() -> [CensusGroup] {
        var buckets: [String: Bucket] = [:]
        var sessions = SessionLookup(builder: self)

        for entry in table.values {
            let rootPid = owner(of: entry.pid)
            guard let root = table[rootPid] else { continue }
            let kind = classify(root)
            let key = "\(kind.category.rawValue)/\(kind.name.lowercased())"
            let isRoot = entry.pid == rootPid

            // the app's own main process reads as the app, not its binary name
            let label = isRoot && kind.category == .apps ? kind.name : nil
            let process = liveProcess(entry, label: label, category: kind.category)

            var bucket = buckets[key] ?? Bucket(category: kind.category, name: kind.name)
            bucket.members.append(process)
            bucket.roles[entry.pid] = role(of: entry, process: process,
                                           category: kind.category, isRoot: isRoot)
            bucket.rootTotals[rootPid, default: 0] += entry.bytes
            bucket.rootMembers[rootPid, default: []].append(process)
            // A helper outside the bundle is shown under its app by name alone (an identifier prefix), which
            // any process can imitate, so Quit on the app never signals it: it acts on the app's own processes.
            if isRoot, process.canQuit, !isJoinedHelper(entry) { bucket.quittableRoots.insert(rootPid) }
            buckets[key] = bucket
        }

        // which apps host a live coding session: a session root whose ancestry reaches the app
        var appOf: [Int: String] = [:]
        for (key, bucket) in buckets where bucket.category == .apps {
            for member in bucket.members { appOf[member.pid] = key }
        }
        var hosted: [String: [String: Int]] = [:]
        for entry in table.values {
            guard let agent = sessions.ownAgent(of: entry.pid) else { continue }
            var current = entry.pid
            var hops = 0
            while hops < 40 {
                if let key = appOf[current] { hosted[key, default: [:]][agent, default: 0] += 1; break }
                guard let parent = table[current]?.ppid, parent > 1, parent != current else { break }
                current = parent
                hops += 1
            }
        }
        return buckets.compactMap { key, bucket in
            group(id: key, from: bucket, sessions: &sessions, hosted: hosted[key] ?? [:])
        }
            .sorted { $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.name < $1.name }
    }

    private func role(of entry: Entry, process: LiveProcess,
                      category: CensusGroup.Category, isRoot: Bool) -> ProcessRole.Described {
        switch category {
        case .apps:
            ProcessRole.of(name: leafName(entry), command: argv(entry), isMain: isRoot)
        case .tools, .system:
            ProcessRole.named(process.friendlyName)
        }
    }

    private func group(id: String, from bucket: Bucket, sessions: inout SessionLookup,
                       hosted: [String: Int]) -> CensusGroup? {
        let members = bucket.members.sorted(by: Self.largestFirst)
        // lead = the root of the biggest tree (two instances of one app share
        // a group; the bigger one speaks for it)
        let leadPid = bucket.rootTotals.max { $0.value < $1.value }?.key
        guard let lead = members.first(where: { $0.pid == leadPid }) ?? members.first
        else { return nil }

        return CensusGroup(
            id: id, name: bucket.name, category: bucket.category,
            role: bucket.category == .system ? ProcessGlossary.systemRole(of: bucket.name) : nil,
            lead: lead, members: members,
            parts: parts(of: members, roles: bucket.roles),
            quit: quitScope(for: bucket),
            programs: bucket.category == .tools
                ? programs(rootMembers: bucket.rootMembers, sessions: &sessions) : [],
            hostedSessions: hosted)
    }

    /// Members grouped by what they do; the app itself first, then by size.
    private func parts(of members: [LiveProcess],
                       roles: [Int: ProcessRole.Described]) -> [CensusPart] {
        var byTitle: [String: (role: ProcessRole.Described, members: [LiveProcess])] = [:]
        for member in members {
            guard let role = roles[member.pid] else { continue }
            byTitle[role.title, default: (role, [])].members.append(member)
        }
        return byTitle.values
            .map { CensusPart(kind: $0.role.kind, title: $0.role.title,
                              one: $0.role.one, many: $0.role.many, members: $0.members) }
            .sorted {
                if ($0.kind == .main) != ($1.kind == .main) { return $0.kind == .main }
                return $0.totalBytes > $1.totalBytes
            }
    }

    private func quitScope(for bucket: Bucket) -> CensusGroup.QuitScope {
        // each root is named with its start time; a root that has already
        // gone cannot be quit and drops out
        let roots = bucket.quittableRoots.sorted().compactMap(ProcessIdentity.of(pid:))
        guard !roots.isEmpty else { return .unavailable }
        switch bucket.category {
        case .apps: return .app(roots)
        case .tools: return .tools(roots)
        case .system: return .unavailable
        }
    }

    private static func largestFirst(_ a: LiveProcess, _ b: LiveProcess) -> Bool {
        a.memoryBytes != b.memoryBytes ? a.memoryBytes > b.memoryBytes : a.pid < b.pid
    }
}
