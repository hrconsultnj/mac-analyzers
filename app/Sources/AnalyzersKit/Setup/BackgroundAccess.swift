import Foundation

/// What the BACKGROUND jobs can read of the protected folders, as the jobs themselves saw it.
///
/// The jobs run from launchd through `agent-runner`, and macOS decides what a program may read by who started it, so
/// the app cannot find out by running `agent-runner` itself (a child of the app is the app's). Instead each time launchd
/// starts `agent-runner` for a job it tries the same folders first and writes the answer here, with the time; Setup
/// reads the file. Until a job has run and written it there is no answer, and Setup says so rather than guessing.
public enum BackgroundAccess {

    public struct Record: Codable, Equatable, Sendable {
        public var checked: Date
        /// `ProtectedPlace.id` to `readable`, `denied`, `missing` or `other`.
        public var places: [String: String]
    }

    public static var file: URL { AnalyzersPaths.userReports.appending(path: "background-access.json") }

    /// Tries the folders and writes the answer. Called by `agent-runner` when launchd starts it for a job; never fails the job.
    public static func record(to url: URL = file, now: Date = Date(),
                              outcomes: [String: PlaceOutcome] = FullDiskAccessProbe.check()) {
        var places: [String: String] = [:]
        for (id, outcome) in outcomes {
            switch outcome {
            case .readable: places[id] = "readable"
            case .denied: places[id] = "denied"
            case .missing: places[id] = "missing"
            case .other: places[id] = "other"
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Record(checked: now, places: places)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// What `agent-runner` calls when launchd starts it for a job, and it must never hold the job up or fail it:
    /// - it is **time-boxed**: the tries run on another thread and the job starts after at most `timeout`, whatever they are doing
    ///   (a protected folder that stalls cannot delay the guard);
    /// - every error is ignored, and the file is written atomically (a reader sees the old answer or the new one, never half);
    /// - it is **cheap and rare**: a few folder opens, and none at all when the answer on disk is younger than `minimumAge`
    ///   (a guard that is restarted over and over writes it once, not each time).
    public static func recordIfDue(to url: URL = file, minimumAge: TimeInterval = 300, timeout: TimeInterval = 2,
                                   now: Date = Date(), outcomes: @escaping @Sendable () -> [String: PlaceOutcome] = { FullDiskAccessProbe.check() }) {
        if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           now.timeIntervalSince(modified) < minimumAge { return }
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            record(to: url, now: now, outcomes: outcomes())
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    /// The newest answer a job wrote, or nil when none has run since this was added.
    public static func read(at url: URL = file) -> (checked: Date, places: [String: PlaceOutcome])? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(Record.self, from: data) else { return nil }
        var places: [String: PlaceOutcome] = [:]
        for (id, word) in record.places {
            switch word {
            case "readable": places[id] = .readable
            case "denied": places[id] = .denied
            case "missing": places[id] = .missing
            default: places[id] = .other(0)
            }
        }
        return (record.checked, places)
    }
}
