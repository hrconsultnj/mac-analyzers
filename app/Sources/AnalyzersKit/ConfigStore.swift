import Foundation
import Observation

/// Tunables the app manages. Every field maps 1:1 to an env var the bash
/// engine already reads (config.local.sh is sourced before defaults resolve),
/// so the engine needs zero changes.
public struct MemoryTunables: Equatable, Sendable {
    public var hardCapMB = 6144        // GUARD_HARD_CAP_MB
    public var hardCapKill = true      // GUARD_HARDCAP_KILL (off = notify-only)
    public var pressureKill = true     // GUARD_PRESSURE_KILL (off = notify-only)
    public var spikeMB = 400           // GUARD_SPIKE_MB
    public var spikeMinMB = 1024       // GUARD_SPIKE_MIN_MB
    public var cpuHogPct = 150         // GUARD_CPU_HOG_PCT
    public var cpuHogTicks = 3         // GUARD_CPU_HOG_TICKS
    public var protectExtra: [String] = []   // ANALYZERS_PROTECT_EXTRA (regex alts)
    public var reclaimApps: [String] = []    // ANALYZERS_RECLAIM_APPS (comma list)
    public init() {}
}

public struct StorageTunables: Equatable, Sendable {
    public var extraCacheGlobs: [String] = []  // ANALYZERS_EXTRA_CACHE_GLOBS (array)
    public var staleApps: [String] = []        // ANALYZERS_STALE_APPS (array)
    public var recordingsDir = ""              // ANALYZERS_RECORDINGS_DIR (the fallback when there is no list of sources)
    /// ANALYZERS_RECORDING_SOURCES: where Old Recordings looks, one `id|state|path` each, in order.
    public var recordingSources: [RecordingSourceEntry] = []
    /// A list of sources exists in config.local.sh (even an empty one): ANALYZERS_RECORDINGS_DIR is then never read.
    public var recordingSourcesConfigured = false
    public var recordingsDays = 90             // ANALYZERS_RECORDINGS_DAYS
    public var toolCaches: [String] = []       // ANALYZERS_TOOL_CACHES (comma ids)
    // Downloads janitor. It is the one cleaner that touches documents rather
    // than rebuildable caches, so its knobs belong in the UI — hand-editing
    // a shell file was the only way to set them.
    public var janitorDownloadsDays = 30       // JANITOR_DOWNLOADS_AGE_DAYS
    public var janitorScreenshotsDays = 14     // JANITOR_SCREENSHOTS_AGE_DAYS
    public var janitorKeepPatterns: [String] = []  // JANITOR_KEEP_PATTERNS (colon list)
    // Code-project cleanup (node_modules / Turborepo cache).
    public var nmAgeDays = 14                  // ANALYZERS_NM_AGE_DAYS
    public var nmRequireClean = true           // ANALYZERS_NM_REQUIRE_CLEAN (1/0)
    public var turboCacheMaxGB = 2             // ANALYZERS_TURBO_CACHE_MAX_GB
    public var worktreeIdleDays = 0            // ANALYZERS_WORKTREE_IDLE_DAYS (0 = off)
    public init() {}
}

public struct NotifyPrefs: Equatable, Sendable {
    // (a `sound` preference used to live here; nothing ever read or wrote it)
    public var timeoutSeconds = 180   // ANALYZERS_NOTIFY_TIMEOUT (alerter fallback)
    public var logViewer = "TextEdit" // ANALYZERS_LOG_VIEWER
    public init() {}
}

/// Reads/writes a clearly-delimited managed block in ~/scripts/config.local.sh
/// (gitignored, machine-local). Hand-written config outside the block is
/// preserved verbatim — same pattern as nvm/conda shell-init blocks.
@MainActor
@Observable
public final class ConfigStore {

    /// The log viewer the user picked, read straight from config.local.sh so
    /// static call sites (GuardControl) honour it without a store instance.
    public static func currentLogViewer() -> String {
        guard let text = try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8),
              let line = text.split(separator: "\n").last(where: { $0.contains("ANALYZERS_LOG_VIEWER=") })
        else { return "TextEdit" }
        let raw = line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) 
        return cleaned.isEmpty ? "TextEdit" : cleaned
    }

    public var memory = MemoryTunables()
    public var storage = StorageTunables()
    public var notify = NotifyPrefs()

    private static let blockStart = "# >>> managed by Mac Analyzers.app — do not edit between markers >>>"
    private static let blockEnd = "# <<< managed by Mac Analyzers.app <<<"

    public init() { load() }

    // MARK: - load

    public func load() {
        guard let text = try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8)
        else { return }

        func value(_ key: String) -> String? {
            // last assignment wins, managed block or not — mirrors bash sourcing
            var result: String?
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\(key)=") else { continue }
                var v = String(trimmed.dropFirst(key.count + 1))
                if v.hasPrefix("(") {
                    // an array: a `#` starts a comment only outside quotes (a folder may be called "Notes #1")
                    var quote: Character?, escaped = false, cut: String.Index?
                    for index in v.indices {
                        let ch = v[index]
                        if let q = quote {
                            if escaped { escaped = false } else if ch == "\\", q == "\"" { escaped = true } else if ch == q { quote = nil }
                        } else if ch == "\"" || ch == "'" { quote = ch } else if ch == "#" { cut = index; break }
                    }
                    if let cut { v = String(v[..<cut]) }
                } else if let hash = v.firstIndex(of: "#"), !v.hasPrefix("\"") && !v.hasPrefix("'") {
                    v = String(v[..<hash])
                }
                v = v.trimmingCharacters(in: .whitespaces)
                if (v.hasPrefix("'") && v.hasSuffix("'")) || (v.hasPrefix("\"") && v.hasSuffix("\"")) {
                    v = String(v.dropFirst().dropLast())
                }
                result = v
            }
            return result
        }

        func arrayValue(_ key: String) -> [String] {
            guard let raw = value(key), raw.hasPrefix("("), raw.hasSuffix(")") else { return [] }
            let inner = raw.dropFirst().dropLast()
            var items: [String] = []
            var current = ""
            var quote: Character?
            var escaped = false
            for ch in inner {
                if let q = quote {
                    // inside double quotes a backslash makes the next character plain, as bash reads it
                    if escaped { current.append(ch); escaped = false }
                    else if ch == "\\", q == "\"" { escaped = true }
                    else if ch == q { quote = nil } else { current.append(ch) }
                } else if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch == " " {
                    if !current.isEmpty { items.append(current); current = "" }
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty { items.append(current) }
            return items
        }

        if let v = value("GUARD_HARD_CAP_MB").flatMap({ Int($0) }) { memory.hardCapMB = v }
        if let v = value("GUARD_HARDCAP_KILL") { memory.hardCapKill = v != "0" }
        if let v = value("GUARD_PRESSURE_KILL") { memory.pressureKill = v != "0" }
        if let v = value("GUARD_SPIKE_MB").flatMap({ Int($0) }) { memory.spikeMB = v }
        if let v = value("GUARD_SPIKE_MIN_MB").flatMap({ Int($0) }) { memory.spikeMinMB = v }
        if let v = value("GUARD_CPU_HOG_PCT").flatMap({ Int($0) }) { memory.cpuHogPct = v }
        if let v = value("GUARD_CPU_HOG_TICKS").flatMap({ Int($0) }) { memory.cpuHogTicks = v }
        if let v = value("ANALYZERS_PROTECT_EXTRA") {
            memory.protectExtra = v.split(separator: "|").map(String.init).filter { !$0.isEmpty }
        }
        if let v = value("ANALYZERS_RECLAIM_APPS") {
            memory.reclaimApps = v.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        storage.extraCacheGlobs = arrayValue("ANALYZERS_EXTRA_CACHE_GLOBS").map(Self.expandHome)
        storage.staleApps = arrayValue("ANALYZERS_STALE_APPS")
        storage.recordingSourcesConfigured = value("ANALYZERS_RECORDING_SOURCES") != nil
        storage.recordingSources = arrayValue("ANALYZERS_RECORDING_SOURCES").compactMap { RecordingSourceEntry(parsing: $0, expandHome: Self.expandHome) }
        if let v = value("ANALYZERS_RECORDINGS_DAYS").flatMap({ Int($0) }), v > 0 { storage.recordingsDays = v }
        if let v = value("JANITOR_DOWNLOADS_AGE_DAYS").flatMap({ Int($0) }) {
            storage.janitorDownloadsDays = v
        }
        if let v = value("JANITOR_SCREENSHOTS_AGE_DAYS").flatMap({ Int($0) }) {
            storage.janitorScreenshotsDays = v
        }
        if let v = value("ANALYZERS_NM_AGE_DAYS").flatMap({ Int($0) }) { storage.nmAgeDays = v }
        if let v = value("ANALYZERS_NM_REQUIRE_CLEAN") { storage.nmRequireClean = v != "0" }
        if let v = value("ANALYZERS_TURBO_CACHE_MAX_GB").flatMap({ Int($0) }) { storage.turboCacheMaxGB = v }
        if let v = value("ANALYZERS_WORKTREE_IDLE_DAYS").flatMap({ Int($0) }) { storage.worktreeIdleDays = v }
        if let v = value("JANITOR_KEEP_PATTERNS") {
            storage.janitorKeepPatterns = v.split(separator: ":")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let v = value("ANALYZERS_RECORDINGS_DIR") { storage.recordingsDir = Self.expandHome(v) }
        if let v = value("ANALYZERS_TOOL_CACHES") {
            storage.toolCaches = v.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let v = value("ANALYZERS_NOTIFY_TIMEOUT").flatMap({ Int($0) }) { notify.timeoutSeconds = v }
        if let v = value("ANALYZERS_LOG_VIEWER") { notify.logViewer = v }
    }

    // MARK: - save

    public func save() throws {
        let fm = FileManager.default
        var existing = (try? String(contentsOf: AnalyzersPaths.configLocal, encoding: .utf8)) ?? ""

        // strip any previous managed block (inclusive of markers)
        if let start = existing.range(of: Self.blockStart),
           let end = existing.range(of: Self.blockEnd) {
            var upper = end.upperBound
            if upper < existing.endIndex, existing[upper] == "\n" {
                upper = existing.index(after: upper)
            }
            existing.removeSubrange(start.lowerBound..<upper)
        }
        existing = existing.trimmingCharacters(in: .whitespacesAndNewlines)

        var out = existing.isEmpty
            ? "# shellcheck shell=bash\n# mac-analyzers — local configuration (see config.example.sh)\n"
            : existing + "\n"
        out += "\n" + Self.blockStart + "\n"
        out += "# Written by the Mac Analyzers menu-bar app (Settings). Anything outside\n"
        out += "# these markers is yours and is never touched.\n"
        out += "GUARD_HARD_CAP_MB=\(memory.hardCapMB)\n"
        out += "GUARD_HARDCAP_KILL=\(memory.hardCapKill ? 1 : 0)\n"
        out += "GUARD_PRESSURE_KILL=\(memory.pressureKill ? 1 : 0)\n"
        out += "GUARD_SPIKE_MB=\(memory.spikeMB)\n"
        out += "GUARD_SPIKE_MIN_MB=\(memory.spikeMinMB)\n"
        out += "GUARD_CPU_HOG_PCT=\(memory.cpuHogPct)\n"
        out += "GUARD_CPU_HOG_TICKS=\(memory.cpuHogTicks)\n"
        if !memory.protectExtra.isEmpty {
            // Escaped: an app name containing a regex metacharacter (a lone
            // "(" in "Foo (beta)") otherwise makes awk abort inside the
            // guard — which silently protects NOTHING while the UI claims
            // the list is active.
            let escaped = memory.protectExtra.map(Self.regexEscape).joined(separator: "|")
            out += "ANALYZERS_PROTECT_EXTRA=\(shellQuote(escaped))\n"
        }
        if !memory.reclaimApps.isEmpty {
            out += "ANALYZERS_RECLAIM_APPS=\(shellQuote(memory.reclaimApps.joined(separator: ",")))\n"
        }
        if !storage.extraCacheGlobs.isEmpty {
            let items = storage.extraCacheGlobs.map { shellQuotePath($0) }.joined(separator: " ")
            out += "ANALYZERS_EXTRA_CACHE_GLOBS=( \(items) )\n"
        }
        if !storage.staleApps.isEmpty {
            let items = storage.staleApps.map { shellQuote($0) }.joined(separator: " ")
            out += "ANALYZERS_STALE_APPS=( \(items) )\n"
        }
        // a list of sources replaces the single folder: it is migrated into the list, and not written twice
        if storage.recordingSources.isEmpty, !storage.recordingSourcesConfigured, !storage.recordingsDir.isEmpty {
            out += "ANALYZERS_RECORDINGS_DIR=\(shellQuotePath(storage.recordingsDir))\n"
        }
        if !storage.recordingSources.isEmpty || storage.recordingSourcesConfigured {
            let items = storage.recordingSources.compactMap { shellQuoteSource($0) }.map { $0 + " " }.joined()
            out += "ANALYZERS_RECORDING_SOURCES=( \(items))\n"
            out += "ANALYZERS_RECORDINGS_DAYS=\(storage.recordingsDays)\n"
        }
        if !storage.toolCaches.isEmpty {
            out += "ANALYZERS_TOOL_CACHES=\(shellQuote(storage.toolCaches.joined(separator: ",")))\n"
        }
        out += "JANITOR_DOWNLOADS_AGE_DAYS=\(storage.janitorDownloadsDays)\n"
        out += "JANITOR_SCREENSHOTS_AGE_DAYS=\(storage.janitorScreenshotsDays)\n"
        if !storage.janitorKeepPatterns.isEmpty {
            out += "JANITOR_KEEP_PATTERNS=\(shellQuote(storage.janitorKeepPatterns.joined(separator: ":")))\n"
        }
        out += "ANALYZERS_NM_AGE_DAYS=\(storage.nmAgeDays)\n"
        out += "ANALYZERS_NM_REQUIRE_CLEAN=\(storage.nmRequireClean ? 1 : 0)\n"
        out += "ANALYZERS_TURBO_CACHE_MAX_GB=\(storage.turboCacheMaxGB)\n"
        out += "ANALYZERS_WORKTREE_IDLE_DAYS=\(storage.worktreeIdleDays)\n"
        out += "ANALYZERS_NOTIFY_TIMEOUT=\(notify.timeoutSeconds)\n"
        out += "ANALYZERS_LOG_VIEWER=\(shellQuote(notify.logViewer))\n"
        out += Self.blockEnd + "\n"

        let tmp = AnalyzersPaths.configLocal.appendingPathExtension("tmp")
        try out.write(to: tmp, atomically: true, encoding: .utf8)
        _ = try fm.replaceItemAt(AnalyzersPaths.configLocal, withItemAt: tmp)
        // what the guard script reads from the rules engine, written with the same numbers (best effort: the script
        // keeps today's constants when the file is not there)
        GuardFallbackFile.write(hardCapMB: memory.hardCapMB, hardCapStop: memory.hardCapKill, pressureStop: memory.pressureKill,
                                neverClosePaths: GuardRules.load().local.neverClose.filter { $0.hasPrefix("/") })
    }

    /// Escape POSIX ERE metacharacters so a literal app name stays literal
    /// when the guard compiles the protect pattern in awk.
    static func regexEscape(_ s: String) -> String {
        var out = ""
        for character in s {
            if "\\^$.[]|()*+?{}".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// Single-quote for bash; embedded single quotes become '\'' .
    /// For non-path strings only — single quotes suppress $HOME expansion.
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quote a PATH for bash: home-prefixed paths are written as
    /// double-quoted "$HOME/…" so bash expands them (single-quoting a
    /// literal $HOME silently breaks the engine's globs/paths).
    private func shellQuotePath(_ s: String) -> String {
        let expanded = Self.expandHome(s)
        let home = AnalyzersPaths.home.path
        guard expanded.hasPrefix(home) else { return shellQuote(expanded) }
        let rest = String(expanded.dropFirst(home.count))
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"$HOME\(rest)\""
    }

    /// One source as a double-quoted element, `"id|state|path"`: a home-prefixed path keeps a live `$HOME`, and every
    /// other character bash would act on inside double quotes (a backslash, a quote, `$`, a backtick) is escaped.
    func shellQuoteSource(_ entry: RecordingSourceEntry) -> String? {
        // the id is a name from the list, and the path one line: anything else cannot be written safely
        guard !entry.id.isEmpty, entry.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !entry.path.contains("\n"), !entry.path.contains("\t"), !entry.path.contains("\r") else { return nil }
        func escape(_ text: String) -> String {
            var out = ""
            for ch in text { if "\\\"$`".contains(ch) { out.append("\\") }; out.append(ch) }
            return out
        }
        let expanded = Self.expandHome(entry.path)
        let home = AnalyzersPaths.home.path
        let path = expanded.hasPrefix(home + "/") || expanded == home ? "$HOME" + escape(String(expanded.dropFirst(home.count))) : escape(expanded)
        return "\"\(entry.id)|\(entry.enabled ? "on" : "off")|\(path)\""
    }

    /// Literal "$HOME/…" or "~/…" (as read from shell config) → real path.
    static func expandHome(_ s: String) -> String {
        let home = AnalyzersPaths.home.path
        if s.hasPrefix("$HOME/") || s == "$HOME" {
            return home + s.dropFirst("$HOME".count)
        }
        if s.hasPrefix("${HOME}/") {
            return home + s.dropFirst("${HOME}".count)
        }
        if s.hasPrefix("~/") || s == "~" {
            return home + s.dropFirst(1)
        }
        return s
    }
}
