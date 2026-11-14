import Foundation

/// What the person has already been shown and answered of the Welcome flow, kept in `~/mac-analyzers/setup-state.json`
/// (the app's records folder, so it survives reinstalling the app; Turn Off › Remove deletes it). It decides when the
/// flow appears on its own: never again once finished or once each step has an answer.
public struct SetupState: Codable, Equatable, Sendable {
    public enum Answer: String, Codable, Sendable { case done, skipped }

    /// The newest version whose steps the person has been shown.
    public var seenVersion: String
    /// Step id to answer.
    public var answers: [String: Answer]
    /// The flow reached its last step.
    public var finished: Bool

    public init(seenVersion: String, answers: [String: Answer] = [:], finished: Bool = false) {
        self.seenVersion = seenVersion
        self.answers = answers
        self.finished = finished
    }

    public static var file: URL { AnalyzersPaths.userRoot.appending(path: "setup-state.json") }

    /// nil when there is no record, or it cannot be read: a person who has never been shown the flow, as far as is known.
    public static func load(at url: URL = file) -> SetupState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SetupState.self, from: data)
    }

    public static func exists(at url: URL = file) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Written atomically; a failure is not the person's problem (the flow would show again), so it is returned, not thrown.
    @discardableResult
    public func save(to url: URL = file) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Deletes the record: Turn Off › Remove from this Mac does, so a reinstall is a new install and gets the Welcome flow again.
    /// (It is the app's own memory of what it has shown, not the person's records: reports, logs, Undo receipts and settings stay.)
    @discardableResult
    public static func remove(at url: URL = file) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    public mutating func record(_ step: WelcomeStep, _ answer: Answer) { answers[step.rawValue] = answer }
}
