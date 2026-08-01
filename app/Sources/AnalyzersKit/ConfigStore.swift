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
    public var recordingsDir = ""              // ANALYZERS_RECORDINGS_DIR
    public var toolCaches: [String] = []       // ANALYZERS_TOOL_CACHES (comma ids)
    public init() {}
}

public struct NotifyPrefs: Equatable, Sendable {
    public var sound = "Glass"        // notify() sound default stays per-call; informational
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
                if let hash = v.firstIndex(of: "#"), !v.hasPrefix("\"") && !v.hasPrefix("'") {
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
            for ch in inner {
                if let q = quote {
                    if ch == q { quote = nil } else { current.append(ch) }
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
            out += "ANALYZERS_PROTECT_EXTRA=\(shellQuote(memory.protectExtra.joined(separator: "|")))\n"
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
        if !storage.recordingsDir.isEmpty {
            out += "ANALYZERS_RECORDINGS_DIR=\(shellQuotePath(storage.recordingsDir))\n"
        }
        if !storage.toolCaches.isEmpty {
            out += "ANALYZERS_TOOL_CACHES=\(shellQuote(storage.toolCaches.joined(separator: ",")))\n"
        }
        out += "ANALYZERS_NOTIFY_TIMEOUT=\(notify.timeoutSeconds)\n"
        out += "ANALYZERS_LOG_VIEWER=\(shellQuote(notify.logViewer))\n"
        out += Self.blockEnd + "\n"

        let tmp = AnalyzersPaths.configLocal.appendingPathExtension("tmp")
        try out.write(to: tmp, atomically: true, encoding: .utf8)
        _ = try fm.replaceItemAt(AnalyzersPaths.configLocal, withItemAt: tmp)
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
