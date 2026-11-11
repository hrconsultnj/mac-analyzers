import Foundation

/// Names for what fills temp folders and AI tools' folders, built from the
/// path and the engine's own reason line. The engine reports a path
/// (`~/.npm/_npx/bef22f83919465d9`); a person needs "codemod". Rules run in
/// order and the first that knows the path names it; an unknown path falls
/// back to its own words with ids and hashes stripped.
enum TempNaming {

    struct Name {
        let title: String
        /// The category column: where this lives.
        let group: String
    }

    static func name(path: String, section: String, reason: String?, isGroup: Bool, count: Int,
                     isCurrent: Bool) -> Name {
        let group = groupTitle(section)
        let last = (path as NSString).lastPathComponent
        let home = NSHomeDirectory()
        let local = path.hasPrefix(home) ? String(path.dropFirst(home.count)) : path

        if isGroup {
            let folder = (path as NSString).deletingLastPathComponent
            let where_ = folderWords(folder)
            return Name(title: "Small Files in \(where_)", group: group)
        }
        if local.hasPrefix("/.npm/_npx/") {
            let package = reason?.components(separatedBy: " · ").last.flatMap { looksLikePackage($0) ? $0 : nil }
            return Name(title: package ?? "Unnamed Tool", group: group)
        }
        if let version = versionFolder(local, parent: "/Library/Application Support/Claude/claude-code/") {
            return Name(title: "Claude Code — \(isCurrent ? "Current" : "Old") Version \(version)", group: group)
        }
        if let version = versionFolder(local, parent: "/Library/Application Support/Claude/claude-code-vm/") {
            return Name(title: "Claude Code VM — \(isCurrent ? "Current" : "Old") Version \(version)", group: group)
        }
        if local.hasPrefix("/Library/Application Support/Claude/") {
            let part = String(local.dropFirst("/Library/Application Support/Claude/".count))
            let known = ["Cache": "Cache", "Code Cache": "Code Cache", "GPUCache": "GPU Cache",
                         "DawnGraphiteCache": "Dawn Graphite Cache", "DawnWebGPUCache": "Dawn WebGPU Cache",
                         "local-agent-mode-sessions": "Agent Sessions", "claude-code-sessions": "Code Sessions",
                         "claude-code-vm/.sdk-version": "VM Version Marker"]
            return Name(title: "Claude App — \(known[part] ?? pretty(part))", group: group)
        }
        if local.hasPrefix("/.claude/") {
            let known = ["projects": "Session Transcripts", "file-history": "File History", "backups": "Backups",
                         "tasks": "Task Lists", "paste-cache": "Pasted Text Cache",
                         "shell-snapshots": "Shell Snapshots", "session-env": "Session Environments"]
            let part = String(local.dropFirst("/.claude/".count))
            return Name(title: "Claude Code — \(known[part] ?? pretty(part))", group: group)
        }
        if path.hasPrefix("/private/tmp/claude-") {
            let rest = path.split(separator: "/").dropFirst(3)      // after /private/tmp/claude-<uid>
            if rest.isEmpty { return Name(title: "Claude Code — Scratch Folder", group: group) }
            let leaf = rest.last.map(String.init) ?? last
            if (leaf as NSString).pathExtension.isEmpty == false {
                return Name(title: "Claude Code — Scratch File \(stripIdentifiers(leaf))", group: group)
            }
            return Name(title: "Claude Code — Session Scratch", group: group)
        }
        if local.hasPrefix("/.codex/") {
            let part = String(local.dropFirst("/.codex/".count))
            if part.hasPrefix(".tmp/") { return Name(title: "Codex Temp Files — \(pretty(String(part.dropFirst(5))))", group: group) }
            let known = ["sessions": "Conversation History", "archived_sessions": "Archived Conversations",
                         "logs_2.sqlite": "Log Database"]
            return Name(title: "Codex — \(known[part] ?? pretty(part))", group: group)
        }
        // a tool kept for its size only: the engine's reason starts with the tool's name
        if let reason, let head = reason.components(separatedBy: " — ").first, reason.contains(" — "),
           section.hasPrefix("other tools") || section.hasPrefix("AI agents — other") || group == Names.Temp.otherTools {
            return Name(title: head, group: group)
        }
        let macOSAreas = ["diagnostics": "Unified Logs", "C": "Per-App Caches", "X": "Code-Signing Clones",
                          "uuidtext": "Log Symbol Data", "log": "System Logs"]
        if group == Names.Temp.managedByMacOS, let known = macOSAreas[last] {
            return Name(title: known, group: group)
        }
        if last.hasPrefix("com.apple.") {
            // the daemon's own name, as macOS spells it
            let parts = stripIdentifiers(String(last.dropFirst("com.apple.".count))).split(separator: ".")
            let words = parts.suffix(2).map(String.init).joined(separator: " ")
            return Name(title: "\(words.isEmpty ? last : words) (macOS)", group: group)
        }
        if let vendor = bundleVendor(last) {
            return Name(title: "\(vendor) Temporary Files", group: group)
        }
        return Name(title: fallback(last), group: group)
    }

    // MARK: - pieces

    static func groupTitle(_ section: String) -> String {
        switch section {
        case "/tmp": Names.Temp.tempFolder
        case "Your temp folder": Names.Temp.yourTempFolder
        case "/var/tmp": Names.Temp.sharedTempFolder
        case "Claude Code": Names.Temp.claudeCode
        case "Codex": Names.Temp.codex
        case "Claude app": Names.Temp.claudeApp
        case "npx-run tools & MCP servers": Names.Temp.nodeTools
        case "other tools": Names.Temp.otherTools
        case "Managed by macOS": Names.Temp.managedByMacOS
        default: section.hasPrefix("other") ? Names.Temp.otherTools : section
        }
    }

    private static func versionFolder(_ local: String, parent: String) -> String? {
        guard local.hasPrefix(parent) else { return nil }
        let rest = String(local.dropFirst(parent.count))
        return rest.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil ? rest : nil
    }

    static func looksLikePackage(_ text: String) -> Bool {
        text.range(of: #"^@?[A-Za-z0-9][A-Za-z0-9._/-]*$"#, options: .regularExpression) != nil
            && !text.hasPrefix("changed") && !text.hasPrefix("a running")
    }

    /// "com.operasoftware.Opera.DnMnVB" → "Opera".
    private static func bundleVendor(_ name: String) -> String? {
        let parts = name.trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".")
        guard parts.count >= 3, parts[0] == "com" || parts[0] == "org" || parts[0] == "io" else { return nil }
        return pretty(String(parts[2]))
    }

    /// A folder in plain words: the user's temp folder, or its last name.
    private static func folderWords(_ folder: String) -> String {
        if folder.contains("/var/folders/"), folder.hasSuffix("/T") { return "Your Temp Folder" }
        if folder == "/private/tmp" { return "the Temp Folder" }
        return pretty((folder as NSString).lastPathComponent)
    }

    /// UUIDs and long hex runs removed, along with the separators they leave.
    static func stripIdentifiers(_ name: String) -> String {
        var text = name.replacingOccurrences(
            of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
            with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[0-9A-Fa-f]{12,}"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[-_.]{2,}"#, with: "-", options: .regularExpression)
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
            .replacingOccurrences(of: "-.", with: ".").replacingOccurrences(of: "_.", with: ".")
    }

    /// A name for a path nothing above knows: a real file name stays as it is,
    /// anything with ids in it loses them, and a name that was only ids says
    /// what kind of file it is.
    static func fallback(_ name: String) -> String {
        let cleaned = stripIdentifiers(name)
        let ext = (name as NSString).pathExtension.lowercased()       // identifiers never carry the extension
        let stem = cleaned.lowercased().hasSuffix("." + ext) ? (cleaned as NSString).deletingPathExtension : cleaned
        let words = stem.split(whereSeparator: { "-_. ".contains($0) }).map(String.init)
            .filter { !$0.allSatisfy(\.isNumber) }
        let lone = words.count == 1 ? words[0].lowercased() : ""
        if words.isEmpty || ["shm", "wal"].contains(lone) || (words.isEmpty && ext.isEmpty) {
            switch ext.isEmpty ? lone : ext {
            case "shm", "wal": return "Database Working File"
            case "db", "sqlite": return "Database File"
            default: return words.isEmpty ? "Temporary Item" : pretty(words.joined(separator: " "))
            }
        }
        // a file with an extension keeps its own name: "d.txt" is what the person knows
        if !ext.isEmpty, ext.count <= 5, ext != "lock" { return cleaned }
        let title = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return ext == "lock" ? title + " Lock" : title
    }

    static func pretty(_ text: String) -> String {
        text.split(whereSeparator: { "-_. /".contains($0) }).filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

}
