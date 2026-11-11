import Foundation

/// The tabs of Temp & Agents.
public enum TempCategory: String, StorageCategory {
    case temporaryFiles, codingAgents, macOS, diskImages

    public var title: String {
        switch self {
        case .temporaryFiles: Names.StorageTab.temporaryFiles
        case .codingAgents: Names.StorageTab.codingAgents
        case .macOS: Names.Category.system
        case .diskImages: Names.StorageTab.diskImages
        }
    }

    public var symbol: String {
        switch self {
        case .temporaryFiles: "tray.full"
        case .codingAgents: "terminal"
        case .macOS: "apple.logo"
        case .diskImages: "externaldrive"
        }
    }
}

/// A disk image mounted inside a temp folder.
public struct TempDiskImage: Identifiable, Hashable, Sendable {
    public let mountPoint: String
    public let imagePath: String
    public let sizeBytes: Int64
    /// Other images mounted from files inside this one; they go when it does.
    public let alsoEjects: [String]
    public var id: String { mountPoint }
    public var name: String { (mountPoint as NSString).lastPathComponent }
}

/// What an audit of temp and agent folders found (or an apply did), as the rows Storage
/// screens share: temporary files by where they live, coding agents' folders by agent, what
/// macOS manages (never touched), and the disk images mounted in temp folders.
public struct TempReview: Sendable {
    public let rows: StorageRows
    public let diskImages: [TempDiskImage]
    /// The numbers at the top: free space, temp on disk, agent folders.
    public let freeSpace: String?
    public let tempOnDisk: String?
    public let agentFolders: String?

    /// Rows a person can tick.
    public var ready: [StorageRow] { rows.choosable }
    public var readyBytes: Int64 { rows.choosableBytes }

    /// `results` shows what an apply did to each row instead of only what a preview would clear.
    public static func build(from run: TempCleanRun, results: Bool = false) -> TempReview {
        let built = run.items.map { item -> StorageRow in
            let reason = item.reason
            let name = TempNaming.name(path: item.path, section: item.section, reason: reason,
                                       isGroup: item.isGroup, count: item.count,
                                       isCurrent: reason == "current version")
            let sentence = sentence(item, reason: reason)
            let category: TempCategory = switch name.group {
            case Names.Temp.tempFolder, Names.Temp.yourTempFolder, Names.Temp.sharedTempFolder: .temporaryFiles
            case Names.Temp.managedByMacOS: .macOS
            default: .codingAgents
            }
            let path = StorageLog.short(item.path)
            if results || item.status == .dry {
                let outcome: String? = results ? item.status.plainLabel : nil
                return StorageRow(id: item.path, category: category.rawValue, group: name.group, title: name.title,
                                  detail: [outcome, results ? nil : sentence, path].compactMap { $0 }.joined(separator: " · "),
                                  bytes: item.sizeBytes, iconPath: results ? nil : item.path)
            }
            // not touched: said in the agreed words where there are some, else in the engine's own
            let why: String = switch item.status {
            case .system, .managed, .skip: Names.Kept.leftForOwner
            case .history: Names.Kept.conversationHistory
            case .keep: Names.Kept.keepList
            case .kept where reason == "current version": Names.Kept.currentVersion
            default: sentence.isEmpty ? item.status.plainLabel : sentence
            }
            return StorageRow(id: item.path, category: category.rawValue, group: name.group, title: name.title,
                              detail: path, bytes: item.sizeBytes, iconPath: item.path, keptReason: why)
        }
        let unique = uniquified(built)
        let images = run.mountedNow.map {
            TempDiskImage(mountPoint: $0.mountPoint, imagePath: $0.imagePath, sizeBytes: $0.sizeBytes,
                          alsoEjects: $0.alsoEjects)
        }
        var facts: [String] = []
        if let free = run.freeSpace { facts.append("free space \(free)") }
        if let tempSize = run.tempOnDisk { facts.append("temp on disk \(tempSize)") }
        if let agents = run.agentFolders { facts.append("agent folders \(agents)") }
        // mounted images are rows of their own tab: shown with what they hold, never ticked (the
        // toolbar's Eject is the one action on them)
        let imageRows = images.map { image -> StorageRow in
            let also = image.alsoEjects.isEmpty ? "" : " · Also ejects \(image.alsoEjects.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))"
            return StorageRow(id: image.mountPoint, category: TempCategory.diskImages.rawValue, group: nil,
                              title: image.name, detail: "Mounted from \(StorageLog.short(image.imagePath))\(also)",
                              bytes: image.sizeBytes,
                              keptReason: "Mounted: eject it from the toolbar to clear what holds it")
        }
        // what the old overview said and the rows do not: what is not on the disk, who is running,
        // the rules in force, and what macOS clears by itself, each over the tab it is about
        var tabNotes: [String: [String]] = [:]
        if let inside = run.insideImages, let bytes = run.insideImagesBytes, bytes > 0 {
            tabNotes[TempCategory.temporaryFiles.rawValue, default: []]
                .append("\(inside) in temp is inside mounted disk images, not on your disk. A plain du would report \(run.plainDu ?? "more").")
        }
        if let rules = run.rulesLine.flatMap(rulesSentence) { tabNotes[TempCategory.temporaryFiles.rawValue, default: []].append(rules) }
        if let selfClean = run.selfCleanLine.flatMap(selfCleanSentence) { tabNotes[TempCategory.temporaryFiles.rawValue, default: []].append(selfClean) }
        var agentParts: [String] = []
        if let n = run.liveClaudeSessions { agentParts.append("\(n) live Claude Code \(n == 1 ? "session" : "sessions")") }
        if let codex = run.codexRunning { agentParts.append(codex ? "Codex is running" : "Codex is closed") }
        if let claude = run.claudeAppRunning { agentParts.append(claude ? "the Claude app is running" : "the Claude app is closed") }
        if !agentParts.isEmpty {
            let text = ListFormatter.localizedString(byJoining: agentParts)
            tabNotes[TempCategory.codingAgents.rawValue, default: []].append(text.prefix(1).uppercased() + text.dropFirst() + ". Folders of anything running are kept.")
        }
        if !images.isEmpty {
            tabNotes[TempCategory.diskImages.rawValue, default: []]
                .append("Their contents are not on your disk. A file that backs an image can't free space until the image is ejected; clearing it ejects it first.")
        }
        return TempReview(rows: StorageRows(unique + imageRows, facts: facts, tabNotes: tabNotes), diskImages: images, freeSpace: run.freeSpace,
                          tempOnDisk: run.tempOnDisk, agentFolders: run.agentFolders)
    }

    /// "24h" or "3d" as a person says it: "a day", "three days", "two weeks".
    static func span(_ number: Int, _ unit: Character) -> String {
        let days = unit == "h" ? max(1, number / 24) : number
        switch days {
        case 1: return "a day"
        case 2: return "two days"
        case 3: return "three days"
        case 7: return "a week"
        case 14: return "two weeks"
        case 30: return "a month"
        default: return "\(days) days"
        }
    }

    private static func first(_ pattern: String, in text: String) -> (Int, Character)? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let match = text[range]
        guard let number = Int(match.filter(\.isNumber)), let unit = match.last(where: { $0 == "h" || $0 == "d" }) else { return nil }
        return (number, unit)
    }

    /// The engine's rules line ("temp idle 24h+ · agent scratch idle 3d+ · …"), as sentences.
    public static func rulesSentence(_ line: String) -> String? {
        guard let temp = first(#"temp idle \d+[hd]"#, in: line), let agent = first(#"agent scratch idle \d+[hd]"#, in: line),
              let npx = first(#"npx tools idle \d+[hd]"#, in: line) else { return nil }
        return "Temporary files are cleared after \(span(temp.0, temp.1)) without use, coding agents' scratch folders after \(span(agent.0, agent.1)) and npx tools after \(span(npx.0, npx.1)). Anything that is open, in use, someone else's or a mounted disk image is never touched."
    }

    /// "macOS also deletes /tmp files untouched for 3+ days each night (tmp_cleaner) — …", as a sentence.
    public static func selfCleanSentence(_ line: String) -> String? {
        guard let range = line.range(of: #"\d+\+ days"#, options: .regularExpression),
              let days = Int(line[range].filter(\.isNumber)) else { return nil }
        return "macOS also clears /tmp by itself every night: files nobody has touched for \(span(days, "d")). It skips mounted disk images and anything in use."
    }

    /// Two things in one group can end up with the same name (three runs of the same npx tool
    /// at different versions): the bigger keeps it, the others say which they are.
    static func uniquified(_ rows: [StorageRow]) -> [StorageRow] {
        var seen: [String: Int] = [:]
        return rows.map { row in
            let key = "\(row.category)|\(row.group ?? "")|\(row.title)"
            seen[key, default: 0] += 1
            guard let count = seen[key], count > 1 else { return row }
            return StorageRow(id: row.id, category: row.category, group: row.group, title: "\(row.title) (\(count))",
                              detail: row.detail, bytes: row.bytes, valueText: row.valueText,
                              iconPath: row.iconPath, keptReason: row.keptReason)
        }
    }

    /// One sentence for the row: the engine's reason, spelled out.
    static func sentence(_ item: TempItem, reason: String?) -> String {
        guard let reason else { return item.status == .dry ? "Idle long enough to clear." : "" }
        // npx rows end with the package name after " · "; the name is the title,
        // and a ready one carries nothing else
        if item.path.contains("/.npm/_npx/") {
            let parts = reason.components(separatedBy: " · ")
            if parts.count == 1, TempNaming.looksLikePackage(reason) { return "Not used in the last 14 days." }
        }
        var text = reason.components(separatedBy: " · ").first ?? reason
        text = text.replacingOccurrences(of: "24h", with: "24 hours")
        text = text.replacingOccurrences(of: "Claude Code deletes", with: "Claude Code removes")
        text = text.replacingOccurrences(of: " (cleanupPeriodDays)", with: "")
        let first = text.prefix(1).uppercased() + text.dropFirst()
        let done = first.hasSuffix(".") ? first : first + "."
        return item.isGroup ? "\(item.count) items. \(done)" : done
    }
}
