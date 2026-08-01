import Foundation

/// Parsed login-items-audit run: the four audit scopes with per-entry
/// verdicts and — the whole point — the exact remediation command per row.
public struct LoginItemEntry: Identifiable, Hashable, Sendable {
    public enum Verdict: String, Sendable {
        case orphan = "ORPHAN"
        case orphanSudo = "NEEDS SUDO"
        case removed = "REMOVED"
        case leftover = "LEFTOVER?"
        case skip = "SKIP"
    }

    public let verdict: Verdict
    public let label: String
    public let plistPath: String?
    public let targetPath: String?
    public let note: String?
    public let sudoCommand: String?
    public var id: String { label + verdict.rawValue }

    /// Short display name (reverse-DNS tail: com.teamviewer.Helper → Helper…
    /// keep two tails for context: teamviewer.Helper).
    public var displayName: String {
        let parts = label.split(separator: ".")
        return parts.count > 2 ? parts.suffix(2).joined(separator: ".") : label
    }
}

public struct LoginItemsRun: Sendable {
    public let header: String
    public let dryRun: Bool
    public let sections: [(title: String, entries: [LoginItemEntry])]

    public var allEntries: [LoginItemEntry] { sections.flatMap(\.entries) }
}

public enum LoginItemsParser {

    /// Parse the newest audit run's lines (as split by LogParser's run
    /// blocks) into structured entries. State machine over the verdict-line
    /// shapes; continuation lines (plist:/target:/sudo …) attach to the
    /// pending entry.
    public static func parse(runHeader: String, lines: [String]) -> LoginItemsRun {
        var sections: [(title: String, entries: [LoginItemEntry])] = []
        var currentTitle = "Audit"
        var current: [LoginItemEntry] = []

        var pending: (verdict: LoginItemEntry.Verdict, label: String, note: String?)?
        var pendingPlist: String?
        var pendingTarget: String?
        var pendingSudo: String?

        func flushPending() {
            guard let p = pending else { return }
            current.append(LoginItemEntry(
                verdict: p.verdict, label: p.label,
                plistPath: pendingPlist, targetPath: pendingTarget,
                note: p.note, sudoCommand: pendingSudo))
            pending = nil
            pendingPlist = nil
            pendingTarget = nil
            pendingSudo = nil
        }

        for line in lines {
            if line.hasPrefix("### ") {
                flushPending()
                if !current.isEmpty || !sections.isEmpty {
                    sections.append((currentTitle, current))
                    current = []
                }
                currentTitle = String(line.dropFirst(4))
                continue
            }
            if line.hasPrefix("plist:") {
                pendingPlist = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("target:") {
                pendingTarget = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("sudo ") {
                pendingSudo = line
                continue
            }
            guard line.hasPrefix("[") else { continue }
            flushPending()

            let verdict: LoginItemEntry.Verdict
            if line.hasPrefix("[ORPHAN·sudo]") { verdict = .orphanSudo }
            else if line.hasPrefix("[ORPHAN]") { verdict = .orphan }
            else if line.hasPrefix("[REMOVED]") { verdict = .removed }
            else if line.hasPrefix("[LEFTOVER?]") { verdict = .leftover }
            else if line.hasPrefix("[SKIP]") { verdict = .skip }
            else { continue }

            guard let close = line.firstIndex(of: "]") else { continue }
            var rest = String(line[line.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
            var note: String?
            // "label  (note) — verify manually" / "label  — long explanation"
            if let dash = rest.range(of: " — ") {
                note = String(rest[dash.upperBound...])
                rest = String(rest[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            if let paren = rest.range(of: #"\s+\(.*\)$"#, options: .regularExpression) {
                let inner = rest[paren].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                note = note.map { "\(inner) — \($0)" } ?? inner
                rest = String(rest[..<paren.lowerBound])
            }
            pending = (verdict, rest.trimmingCharacters(in: .whitespaces), note)
        }
        flushPending()
        sections.append((currentTitle, current))

        return LoginItemsRun(
            header: runHeader,
            dryRun: runHeader.contains("DRY RUN"),
            sections: sections.filter { !$0.entries.isEmpty }
        )
    }
}
