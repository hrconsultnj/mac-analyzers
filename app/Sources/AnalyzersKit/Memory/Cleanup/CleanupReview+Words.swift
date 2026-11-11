import Foundation

/// The cleaner's findings in plain words: what each line's engine token means,
/// and what the numbered sections are called. The engine's lines are the
/// source; none of its tokens reach the screen.
extension CleanupReview {

    static func candidate(from item: ReapItem, group: String, ordinal: Int, title: String) -> CleanupCandidate? {
        // an app on the quit list that is not running has nothing to show
        if item.status == .skip, item.description.contains("— not running") { return nil }
        // an app that hosts a live coding session is kept, and quitting it is the person's own act
        if item.status == .skip, let range = item.description.range(of: " — hosts ") {
            let name = String(item.description[..<range.lowerBound])
            let hosted = item.description[range.upperBound...].prefix { $0.isNumber }
            return CleanupCandidate(
                id: "host-\(ordinal)", pid: nil, name: name, detail: nil,
                reason: "Hosts \(hosted.isEmpty ? "a" : String(hosted)) live coding session\(hosted == "1" || hosted.isEmpty ? "" : "s"). Quit it yourself to end \(hosted == "1" || hosted.isEmpty ? "it" : "them").",
                group: group, memoryMB: nil, count: 1, state: .kept, category: .apps,
                groupName: "Your list", identity: nil)
        }
        let parsed = Parsed(description: item.description)
        let state: CleanupCandidate.State = switch item.status {
        case .dry: parsed.isAppQuit ? .willBeAskedToQuit : .readyToClose
        case .killed: .closed
        case .quit: .quit
        case .reported: .leftAlone
        case .exempt: .kept
        case .gone: .alreadyGone
        case .skip: .notApproved
        }
        let reason = item.status == .exempt ? "Belongs to a live session, so it is not closed."
            : item.status == .skip ? "You left it out of this cleanup."
            : parsed.reason ?? Self.reason(forGroup: group)
        let category = parsed.isAppQuit ? CleanupCandidate.Category.apps
            : item.status == .exempt ? .liveSessions : category(forTitle: title)
        // grouped by where it runs (the project), else by what it is
        let groupName = parsed.isAppQuit ? "Your list" : parsed.detail ?? parsed.name
        // the engine exempts the sessions it knows; the app checks the same list again at the
        // moment the review is read, so a session it missed still cannot be ticked
        if state == .readyToClose, let pid = item.pid,
           let agent = CodingAgentHosts.liveSessionAgent(pid: pid) {
            return CleanupCandidate(id: "\(pid)-\(ordinal)", pid: pid, name: parsed.name, detail: parsed.detail,
                                    reason: "Kept — part of a live \(agent) session.", group: group,
                                    memoryMB: item.mb, count: 1, state: .kept, category: .liveSessions,
                                    groupName: "Live sessions", identity: nil)
        }
        let identity = (state == .readyToClose) ? item.pid.flatMap(ProcessIdentity.of(pid:)) : nil
        return CleanupCandidate(id: "\(item.pid.map(String.init) ?? "row")-\(ordinal)", pid: item.pid,
                                name: parsed.name, detail: parsed.detail, reason: reason, group: group,
                                memoryMB: item.mb, count: 1, state: state,
                                category: category, groupName: groupName, identity: identity)
    }

    /// What one description line says, in words.
    struct Parsed {
        var name: String
        var detail: String?
        var reason: String?
        var isAppQuit = false

        init(description raw: String) {
            let description = raw.trimmingCharacters(in: .whitespaces)

            // reclaim's app quit: "would quit: Opera" / "Opera"
            if description.hasPrefix("would quit: ") {
                name = String(description.dropFirst("would quit: ".count))
                reason = "On your list of apps to quit."
                isAppQuit = true
                return
            }

            // "stale-dev (25h): next-server (v16.2.7)", "idle-simulator (idle 21m of 20m): iPhone 18 Pro"
            if let match = description.range(of: #"^([a-z][a-z-]*) \(([^)]*)\): "#, options: .regularExpression) {
                let head = String(description[match])
                let rest = String(description[match.upperBound...])
                let token = String(head.prefix { $0 != " " })
                let inside = head.range(of: #"\(([^)]*)\)"#, options: .regularExpression)
                    .map { String(head[$0]).dropFirst().dropLast() } ?? ""
                (name, detail, reason) = Self.fromToken(token, inside: String(inside), rest: rest)
                return
            }

            // "orphan-mcp: <command>"
            if description.hasPrefix("orphan-mcp: ") {
                let rest = String(description.dropFirst("orphan-mcp: ".count))
                name = ProcessNaming.name(forCommand: rest)
                detail = ProcessNaming.project(inCommand: rest)
                reason = "The session that started it has ended."
                return
            }

            // "in use — next-server (no session or terminal in its project): next-server (v16.3.1)"
            if description.hasPrefix("in use — ") {
                let body = String(description.dropFirst("in use — ".count))
                if let colon = body.range(of: "): ") {
                    let note = body[..<colon.lowerBound]
                    let command = String(body[colon.upperBound...])
                    name = ProcessNaming.name(forCommand: command)
                    detail = ProcessNaming.project(inCommand: command)
                    if let open = note.firstIndex(of: "(") {
                        let why = note[note.index(after: open)...]
                        reason = "In use — \(why)."
                    } else {
                        reason = "In use right now."
                    }
                } else {
                    name = ProcessNaming.name(forCommand: body)
                    reason = "In use right now."
                }
                return
            }

            // "up 189h  /path/to/thing"
            if let up = description.range(of: #"^up (\d+)h\s+"#, options: .regularExpression) {
                let hours = description[up].dropFirst(3).prefix { $0.isNumber }
                let command = String(description[up.upperBound...])
                name = ProcessNaming.name(forCommand: command)
                detail = ProcessNaming.project(inCommand: command)
                reason = "Running for \(hours) hours with nothing that started it."
                return
            }

            // "supabase:etal-crm  11 containers  …  — would stop (containers kept …)"
            if description.hasPrefix("supabase:") || description.hasPrefix("orbstack-") {
                let first = String(description.prefix { $0 != " " })
                name = first.hasPrefix("supabase:")
                    ? "Supabase stack" : "Container stack"
                detail = first.contains(":") ? String(first.split(separator: ":", maxSplits: 1)[1]) : first
                if let dash = description.range(of: "— ") {
                    reason = Self.sentence(String(description[dash.upperBound...]))
                } else {
                    reason = "A stack of containers that no live session needs."
                }
                return
            }

            // a plain command line (reclaim, orphans)
            name = ProcessNaming.name(forCommand: description)
            detail = ProcessNaming.project(inCommand: description)
            reason = nil
        }

        private static func fromToken(_ token: String, inside: String, rest: String)
            -> (String, String?, String?) {
            let minutes = inside.range(of: #"idle (\d+)m"#, options: .regularExpression)
                .map { String(inside[$0]).dropFirst(5).dropLast() }
            switch token {
            case "stale-dev":
                let hours = inside.prefix { $0.isNumber }
                return (ProcessNaming.name(forCommand: rest), ProcessNaming.project(inCommand: rest),
                        "Running for \(hours) hours — a dev server you can start again.")
            case "stale-playwright":
                let mins = inside.prefix { $0.isNumber }
                return ("Test browser", ProcessNaming.project(inCommand: rest),
                        "Left running for \(mins) minutes.")
            case "idle-simulator":
                return ("iOS Simulator", rest, "Idle for \(minutes.map(String.init) ?? "a while") minutes.")
            case "idle-emulator":
                return ("Android emulator", rest, "Idle for \(minutes.map(String.init) ?? "a while") minutes.")
            case "idle-metro":
                return ("Metro bundler", ProcessNaming.project(inCommand: rest),
                        "Idle for \(minutes.map(String.init) ?? "a while") minutes — nothing is using it.")
            default:
                let words = token.replacingOccurrences(of: "-", with: " ")
                return (ProcessNaming.name(forCommand: rest), ProcessNaming.project(inCommand: rest),
                        words.prefix(1).uppercased() + words.dropFirst() + ".")
            }
        }

        /// "would stop (containers kept, volumes untouched)" → a sentence.
        private static func sentence(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let first = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
            return first.hasSuffix(".") ? first : first + "."
        }
    }

    // MARK: - sections and kept helpers

    /// The engine's numbered section heading as a plain name.
    static func groupName(forTitle title: String) -> String {
        let number = title.prefix { $0.isNumber }
        switch number {
        case "1": return "Left behind by a closed session"
        case "2": return "Orphaned developer tools"
        case "3": return "Dev servers running more than a day"
        case "4": return "Test browsers left running"
        case "5": return "Kept for live sessions"
        case "6": return "Editor helpers using a lot of memory"
        case "7": return "Idle emulators and simulators"
        case "8": return "Idle Gradle and Kotlin daemons"
        case "9": return "Build leftovers"
        case "10": return "Dev servers nobody is using"
        case "11": return "Idle container stacks"
        default:
            if title.hasPrefix("Quitting heavy apps") { return "Apps on your list" }
            if title.hasPrefix("Sweeping dev tooling") { return "Developer tools" }
            return "Other"
        }
    }

    /// The kind of thing a numbered section finds.
    static func category(forTitle title: String) -> CleanupCandidate.Category {
        switch title.prefix(while: { $0.isNumber }) {
        case "3", "10": .devServers
        case "1", "2": .orphanedTools
        case "4", "7": .emulators
        case "8", "9": .buildHelpers
        case "11": .containers
        case "6": .editorHelpers
        case "5": .liveSessions
        default: title.hasPrefix("Quitting heavy apps") ? .apps : .orphanedTools
        }
    }

    /// Why a plain command line is on the list, by the finding it came under.
    static func reason(forGroup group: String) -> String {
        switch group {
        case "Left behind by a closed session": "The session that started it has ended."
        case "Orphaned developer tools": "Whatever started it is gone."
        case "Dev servers running more than a day": "Has been running for more than a day."
        case "Test browsers left running": "A test browser nobody is using."
        case "Editor helpers using a lot of memory": "Uses a lot of memory and has been up for days."
        case "Build leftovers": "A build helper whose parent is gone."
        case "Dev servers nobody is using": "Nobody is connected to it."
        case "Developer tools": "Picked up by the sweep of developer tools."
        default: group
        }
    }

    /// The label of a kept aggregate ("Claude", "context7-mcp", "mcp") as a name.
    static func keptName(_ label: String) -> String {
        if label.lowercased().contains("mcp") || label == "server.js" || label == "server.bundle.js"
            || label == "index.js" || label == "npm" || label == "shadcn" || label == "null" {
            return "Session helpers (\(label))"
        }
        return label
    }
}
