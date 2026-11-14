import Foundation

/// Reads, migrates and saves the list of recording sources, through `ConfigStore` (the only thing that writes
/// config.local.sh). The pure steps are static, so a probe can check them without a window.
@MainActor
public enum RecordingSourcesStore {

    /// The days an old recording has to be, as the Sources window offers them.
    public static let dayChoices = [30, 60, 90, 180, 365]

    /// The sources the Sources window starts from: everything discovery found, with the saved switches. When nothing was
    /// saved yet and a single recordings folder is set (`ANALYZERS_RECORDINGS_DIR`, today's way), that folder is migrated
    /// in: it becomes the discovered source that has the same folder, switched ON, or the first custom folder. It stays
    /// on exactly as it is today.
    public static func startingSources(config: ConfigStore, readers: RecordingReaders, allowed: Set<String> = []) -> [RecordingSource] {
        let saved = config.storage.recordingSources
        let discovered = RecordingDiscovery.discover(readers: readers, saved: saved, allowed: allowed)
        guard saved.isEmpty, !config.storage.recordingsDir.isEmpty else { return discovered }
        return migrating(folder: config.storage.recordingsDir, into: discovered, readers: readers, allowed: allowed)
    }

    /// `folder` kept on: a discovered source that already has that folder is switched on; any other folder becomes a custom source.
    public static func migrating(folder: String, into sources: [RecordingSource], readers: RecordingReaders,
                                 allowed: Set<String>) -> [RecordingSource] {
        let folder = trimmed(folder)
        var result = sources
        if let at = result.firstIndex(where: { $0.offer != .notOffered && $0.path.map(trimmed) == folder }) {
            result[at].enabled = true
        } else {
            result.append(RecordingDiscovery.custom(RecordingSourceEntry(id: RecordingSource.customID, enabled: true, path: folder),
                                                    readers: readers, allowed: allowed))
        }
        return result
    }

    public enum Added: Equatable, Sendable {
        /// The list with the folder in it.
        case added([RecordingSource])
        /// An existing source already covers this folder: it is switched on instead of added twice.
        case alreadyListed([RecordingSource], title: String)
        case refused(String)
    }

    /// A folder the person picked. The same refusals as the engine's; one that a discovered source already covers becomes
    /// that source.
    public static func adding(folder: String, to sources: [RecordingSource], readers: RecordingReaders, isLink: Bool,
                              allowed: Set<String>) -> Added {
        let folder = trimmed(folder)
        if let why = RecordingFolderRule.refusal(folder, home: readers.home, isLink: isLink) { return .refused(why) }
        var result = sources
        if let at = result.firstIndex(where: { $0.offer != .notOffered && $0.path.map(trimmed) == folder }) {
            result[at].enabled = true
            return .alreadyListed(result, title: result[at].title)
        }
        result.append(RecordingDiscovery.custom(RecordingSourceEntry(id: RecordingSource.customID, enabled: true, path: folder),
                                                readers: readers, allowed: allowed))
        return .added(result)
    }

    /// What is written to config.local.sh: every source that can be offered and has a folder, with its switch, in the
    /// order shown.
    public static func entries(from sources: [RecordingSource]) -> [RecordingSourceEntry] {
        sources.compactMap { source in
            guard source.offer != .notOffered, let path = source.path else { return nil }
            return RecordingSourceEntry(id: source.kind, enabled: source.enabled, path: path)
        }
    }

    /// Saves the list and how old a recording has to be. `ANALYZERS_RECORDINGS_DIR` is left out of the managed block from
    /// now on (the list holds it).
    public static func save(_ sources: [RecordingSource], days: Int, in config: ConfigStore) throws {
        config.storage.recordingSources = entries(from: sources)
        config.storage.recordingsDays = dayChoices.contains(days) ? days : 90
        try config.save()
    }

    /// "3 on · 1 needs access": for a row of Setup's.
    public static func summary(_ sources: [RecordingSource]) -> String {
        let offered = sources.filter { $0.offer != .notOffered }
        let on = offered.filter(\.enabled)
        var parts = ["\(on.count) on"]
        let needs = on.filter { if case .needsAccess = $0.access { true } else { false } }.count
        if needs > 0 { parts.append("\(needs) needs access") }
        return parts.joined(separator: " · ")
    }

    private static func trimmed(_ path: String) -> String { path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path }
}
