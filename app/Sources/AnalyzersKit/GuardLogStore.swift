import Foundation
import Observation

/// Live model behind the menu-bar feed: parsed guard events, kill badge,
/// pause state, and auto-clean last-run facts. Watches guard.log for appends
/// (DispatchSource on the fd — the scripts append in place, so the inode is
/// stable; per research, FSEvents only becomes necessary if rotation is added).
@MainActor
@Observable
public final class GuardLogStore {

    public private(set) var events: [GuardEvent] = []
    public private(set) var killsToday: Int = 0
    public private(set) var guardPaused = false
    public private(set) var lastMemoryCleanRun: Date?
    public private(set) var lastStorageCleanRun: Date?
    public private(set) var storageDailySummary: String?
    public private(set) var storageDeepSummary: String?
    public private(set) var latestForensics: URL?
    public private(set) var pressure: LiveStats.Pressure = .normal
    public private(set) var topProcesses: [LiveProcess] = []
    public private(set) var monitorProcesses: [LiveProcess] = []
    public private(set) var monitorGroups: [ProcessGroup] = []
    public private(set) var disk: DiskUsage?
    /// "106Gi avail (76% used)" from the last storage-clean run's log.
    public private(set) var lastCleanDiskState: String?
    /// What is actually installed and loaded — asked of launchd, not assumed.
    public private(set) var engine: EngineStatus?

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1

    /// Display-only stats floor: "Clear" hides events/kills before this
    /// moment. The guard.log itself is never touched — it stays the full
    /// audit trail.
    private var clearMarker: URL {
        AnalyzersPaths.memoryReports.appending(path: ".menu-stats-cleared")
    }
    private var clearedAt: Date? {
        guard let raw = try? String(contentsOf: clearMarker, encoding: .utf8),
              let epoch = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    public init() {
        reload()
        startWatching()
    }

    /// Everything reload gathers, computed OFF the main thread (ps shell-outs
    /// + log parses froze pane switches when done inline — blueprint P0).
    private struct Payload: Sendable {
        let events: [GuardEvent]
        let killsToday: Int
        let guardPaused: Bool
        let lastMemoryCleanRun: Date?
        let lastStorageCleanRun: Date?
        let storageDailySummary: String?
        let storageDeepSummary: String?
        let latestForensics: URL?
        let pressure: LiveStats.Pressure
        let sample: LiveStats.Sample
        let engine: EngineStatus
        let disk: DiskUsage?
        let lastCleanDiskState: String?
    }

    /// In-flight guard: this is the heaviest read in the app (process table
    /// + three log parses + disk). Menu ticks, pane appears and file-watch
    /// events all call it — without this they stacked.
    @ObservationIgnored private var reloading = false
    @ObservationIgnored private var reloadAgain = false

    /// Cached-first: published values stay on screen while the fresh payload
    /// is computed in the background, then apply atomically on main.
    public func reload() {
        // Coalesced, not dropped. Asking during a refresh used to be ignored
        // outright, so quitting an app and refreshing in the same breath could
        // leave the dead row on screen until the next tick.
        guard !reloading else { reloadAgain = true; return }
        reloading = true
        let floor = clearedAt
        Task.detached(priority: .userInitiated) { [weak self] in
            let payload = Payload(
                events: GuardLogParser.recentEvents(fromLog: AnalyzersPaths.guardLog, after: floor),
                killsToday: GuardLogParser.killsToday(fromLog: AnalyzersPaths.guardLog, after: floor),
                guardPaused: FileManager.default.fileExists(atPath: AnalyzersPaths.guardPauseFlag.path),
                lastMemoryCleanRun: AnalyzersPaths.modificationDate(of: AnalyzersPaths.memoryAutoCleanLog),
                lastStorageCleanRun: AnalyzersPaths.modificationDate(of: AnalyzersPaths.storageAutoCleanLog),
                storageDailySummary: Self.lastStorageSummary(mode: "daily"),
                storageDeepSummary: Self.lastStorageSummary(mode: "deep"),
                latestForensics: AnalyzersPaths.latestForensics(),
                pressure: LiveStats.memoryPressure(),
                // ONE process-table sweep feeds all three lists (they must
                // agree anyway); this used to be three separate walks.
                sample: LiveStats.sample(),
                engine: EngineStatus.probe(),
                disk: LiveStats.diskUsage(),
                lastCleanDiskState: Self.lastFreeSpaceLine())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(payload)
                self.reloading = false
                if self.reloadAgain {
                    self.reloadAgain = false
                    self.reload()
                }
            }
        }
    }

    private func apply(_ p: Payload) {
        events = p.events
        killsToday = p.killsToday
        guardPaused = p.guardPaused
        lastMemoryCleanRun = p.lastMemoryCleanRun
        lastStorageCleanRun = p.lastStorageCleanRun
        storageDailySummary = p.storageDailySummary
        storageDeepSummary = p.storageDeepSummary
        latestForensics = p.latestForensics
        pressure = p.pressure
        topProcesses = p.sample.top
        monitorProcesses = p.sample.all
        monitorGroups = p.sample.groups
        engine = p.engine
        disk = p.disk
        lastCleanDiskState = p.lastCleanDiskState
    }

    /// Hide everything shown so far (badge + rows). Log untouched.
    public func clearStats() {
        try? String(Date().timeIntervalSince1970.description)
            .write(to: clearMarker, atomically: true, encoding: .utf8)
        reload()
    }

    public enum PauseError: LocalizedError {
        case couldNotWrite(String)
        public var errorDescription: String? {
            switch self {
            case .couldNotWrite(let detail): detail
            }
        }
    }

    /// Verified, not assumed: create the directory if the engine has never
    /// run, write (or remove) the flag, then RE-READ and compare against
    /// intent before telling the user it worked. The UI used to flip to
    /// "Paused" while the guard kept acting.
    public func setGuardPaused(_ paused: Bool) throws {
        let fm = FileManager.default
        let flag = AnalyzersPaths.guardPauseFlag
        try? fm.createDirectory(at: flag.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if paused {
            if !fm.createFile(atPath: flag.path, contents: Data()) {
                throw PauseError.couldNotWrite("Could not create the pause marker at \(flag.path).")
            }
        } else {
            try? fm.removeItem(at: flag)
        }
        let actual = fm.fileExists(atPath: flag.path)
        guard actual == paused else {
            throw PauseError.couldNotWrite(
                paused ? "The pause marker could not be written, so the guard is still acting."
                       : "The pause marker could not be removed, so the guard is still paused.")
        }
        guardPaused = actual
    }

    @ObservationIgnored private var watchReloadPending = false

    /// Collapse a burst of log appends into a single refresh.
    private func scheduleWatchReload() {
        guard !watchReloadPending else { return }
        watchReloadPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.watchReloadPending = false
            self?.reload()
        }
    }

    // MARK: - file watching

    private func startWatching() {
        stopWatching()
        let fd = open(AnalyzersPaths.guardLog.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            MainActor.assumeIsolated {
                // Debounced: while memory pressure is elevated the guard
                // appends a line every 15 s, and each one used to trigger a
                // full refresh — permanently, whether or not anything is
                // on screen. Bursts now collapse into one refresh.
                self.scheduleWatchReload()
                // delete/rename invalidates the fd-based source — re-arm on the
                // (possibly re-created) file
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.startWatching()
                }
            }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedFD = -1
    }

    // MARK: - storage summary

    /// Last "Free space now: 106Gi avail (76% used)" line the storage clean
    /// logged — the disk state as of the last run.
    private nonisolated static func lastFreeSpaceLine() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: AnalyzersPaths.storageAutoCleanLog)
        else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 65_536
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n")
            .last { $0.contains("Free space now:") }
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "Free space now: ", with: "")
                    .replacingOccurrences(of: "Gi avail", with: " GB free")
            }
    }

    /// Last "DONE — freed ~4 MB [mode=daily]." line for a given mode.
    private nonisolated static func lastStorageSummary(mode: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: AnalyzersPaths.storageAutoCleanLog)
        else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 65_536
        let offset = size > window ? size - window : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n")
            .last { $0.contains("DONE — freed") && $0.contains("[mode=\(mode)]") }
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "DONE — ", with: "")
                    .replacingOccurrences(of: " [mode=\(mode)]", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
    }
}
