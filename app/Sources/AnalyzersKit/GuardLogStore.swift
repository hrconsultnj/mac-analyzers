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
    public private(set) var storageLastRunSummary: String?
    public private(set) var latestForensics: URL?

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedFD: Int32 = -1

    public init() {
        reload()
        startWatching()
    }

    public func reload() {
        events = GuardLogParser.recentEvents(fromLog: AnalyzersPaths.guardLog)
        killsToday = GuardLogParser.killsToday(fromLog: AnalyzersPaths.guardLog)
        guardPaused = FileManager.default.fileExists(atPath: AnalyzersPaths.guardPauseFlag.path)
        lastMemoryCleanRun = AnalyzersPaths.modificationDate(of: AnalyzersPaths.memoryAutoCleanLog)
        lastStorageCleanRun = AnalyzersPaths.modificationDate(of: AnalyzersPaths.storageAutoCleanLog)
        storageLastRunSummary = Self.lastStorageSummary()
        latestForensics = AnalyzersPaths.latestForensics()
    }

    public func setGuardPaused(_ paused: Bool) {
        let flag = AnalyzersPaths.guardPauseFlag
        if paused {
            FileManager.default.createFile(atPath: flag.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: flag)
        }
        guardPaused = paused
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
                self.reload()
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

    /// Last "DONE — freed ~4 MB [mode=daily]." line from the storage log.
    private nonisolated static func lastStorageSummary() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: AnalyzersPaths.storageAutoCleanLog)
        else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 16_384
        let offset = size > window ? size - window : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n")
            .last { $0.contains("DONE — freed") }
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "DONE — ", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
    }
}
