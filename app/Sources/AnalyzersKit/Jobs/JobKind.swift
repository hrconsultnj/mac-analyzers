import Foundation

/// What a job is for.
public enum JobIntent: String, Codable, Sendable {
    case preview
    case apply
    /// Read-only or one-shot: a report, a snapshot, an eject, an install.
    case run
}

/// One script invocation: the script and the arguments after it.
public struct EngineCommand: Sendable, Equatable {
    public let script: URL
    public let args: [String]
    public init(script: URL, args: [String]) {
        self.script = script
        self.args = args
    }
}

/// Why a job could not be turned into engine commands.
public enum JobKindError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupported(JobKind, JobIntent)
    case missingOption(String)

    public var description: String {
        switch self {
        case .unsupported(let kind, let intent):
            "\(kind.rawValue) has no \(intent.rawValue) mode."
        case .missingOption(let name):
            "Missing option: \(name)."
        }
    }
}

/// The one name table for everything the app runs through the engine: which
/// script, which log it writes, and exactly which arguments each intent
/// passes. What a kind is called, drawn as, and tinted lives in
/// `UIComponents` (`JobKind+Presentation`), never here.
///
/// Scripts are dry-run unless told otherwise, so `previewArgs` always starts
/// with `--dry-run` (or is a read-only mode) and only `applyArgs` can carry
/// an action flag. `JobStore` is the only thing that builds an apply.
public enum JobKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case memoryClean, reclaim, storageClean, janitor, tempClean, tmReclaim, spotlight, loginItems
    case unusedApps, recordings
    case networkSnapshot, memoryReport, storageReport
    case installAgents, uninstallAgents, sudoersInstall, eject

    public var id: String { rawValue }

    // MARK: - what it is

    /// Kinds that change the user's Mac and therefore have a preview and an
    /// apply. Everything else only ever runs (`JobIntent.run`).
    public var isCleaner: Bool {
        switch self {
        case .memoryClean, .reclaim, .storageClean, .janitor, .tempClean, .tmReclaim,
             .spotlight, .loginItems, .unusedApps, .recordings: true
        case .networkSnapshot, .memoryReport, .storageReport,
             .installAgents, .uninstallAgents, .sudoersInstall, .eject: false
        }
    }

    /// Only the admin-rights rule installer asks for a password.
    public var needsPrivilege: Bool { self == .sudoersInstall }

    /// Can the user get it back? The janitor and temp clean use the Trash
    /// (temp clean unless permanent is chosen); the storage cleaner deletes,
    /// and stopping a process is not undoable.
    public func isRecoverable(_ options: JobOptions) -> Bool {
        switch self {
        case .janitor: true
        case .tempClean: !options.permanent
        default: false
        }
    }

    // MARK: - where it lives

    /// The log the script appends its run blocks to. nil for kinds that write
    /// a report file or nothing readable as runs.
    public var log: EngineLog? {
        switch self {
        case .memoryClean: .memoryClean
        case .reclaim: .reclaim
        case .storageClean: .storageClean
        case .janitor: .janitor
        case .tempClean, .eject: .tempSpace
        case .spotlight: .spotlightAudit
        case .loginItems: .loginItems
        case .unusedApps: .cleanupApps
        case .recordings: .cleanupRecordings
        case .tmReclaim, .networkSnapshot, .memoryReport, .storageReport,
             .installAgents, .uninstallAgents, .sudoersInstall: nil
        }
    }

    /// The script that does the work (the first, for kinds that run two).
    public var script: URL { scripts[0] }

    /// Every script a run of this kind starts, in order. The two agent
    /// installers are one job because the Setup screen runs them together.
    public var scripts: [URL] {
        let root = AnalyzersPaths.suiteRoot
        switch self {
        case .memoryClean: return [AnalyzersPaths.memoryCleanScript]
        case .reclaim: return [AnalyzersPaths.reclaimScript]
        case .storageClean: return [AnalyzersPaths.storageCleanScript]
        case .janitor: return [AnalyzersPaths.janitorScript]
        case .tempClean, .eject: return [AnalyzersPaths.tempCleanScript]
        case .spotlight: return [AnalyzersPaths.spotlightAuditScript]
        case .loginItems: return [root.appending(path: "storage-analyzer/login-items-audit.sh")]
        case .tmReclaim: return [root.appending(path: "storage-analyzer/tm-reclaim.sh")]
        case .unusedApps, .recordings: return [root.appending(path: "storage-analyzer/cleanup.sh")]
        case .networkSnapshot: return [AnalyzersPaths.networkScript]
        case .memoryReport: return [AnalyzersPaths.memoryAnalyzeScript]
        case .storageReport: return [AnalyzersPaths.storageAnalyzeScript]
        case .installAgents, .uninstallAgents:
            return [root.appending(path: "memory-analyzer/memory-manage-agents.sh"),
                    root.appending(path: "storage-analyzer/storage-manage-agents.sh")]
        case .sudoersInstall: return [root.appending(path: "storage-analyzer/storage-manage-agents.sh")]
        }
    }

    // MARK: - when it fails

    /// What to call this action in "Couldn't ___": the words the screens used
    /// before jobs ("run the audit", "write the report"), so a failure reads
    /// the same wherever it is shown.
    public func failureVerb(_ intent: JobIntent, options: JobOptions) -> String {
        switch (self, intent) {
        case (.spotlight, .preview), (.tempClean, .preview): return "run the audit"
        case (.spotlight, .apply): return "apply fences"
        case (.eject, _):
            let name = options.mountPoint.map { ($0 as NSString).lastPathComponent }
            return "eject \(name.flatMap { $0.isEmpty ? nil : $0 } ?? "the disk image")"
        case (.memoryReport, _), (.storageReport, _): return "write the report"
        case (.networkSnapshot, _): return "take the snapshot"
        case (.installAgents, _): return "install the background jobs"
        case (.uninstallAgents, _): return "turn off the background jobs"
        default:
            switch intent {
            case .preview: return "preview"
            case .apply: return "apply"
            case .run: return "run it"
            }
        }
    }

    /// The sentence for a script that ended with `exitCode`. A missing script
    /// is the "cleaning script" for a cleaner and the app's own incomplete
    /// copy for the two agent installers.
    public func failureMessage(exitCode: Int32, intent: JobIntent, options: JobOptions) -> String {
        let verb = failureVerb(intent, options: options)
        if exitCode == 127, self == .installAgents || self == .uninstallAgents {
            return "Couldn't \(verb): the app's copy of the analyzer scripts is incomplete."
        }
        return ExitExplanation.explain(exitCode: exitCode, verb: verb)
    }

    // MARK: - approval

    /// The engine flag that limits an apply to the reviewed list: every cleaner
    /// whose script understands one is named here, and ONLY those, because a
    /// script that does not know the flag stops with "unknown option".
    ///
    /// The cleaners that take NO list, each with the reason (turn one on by moving
    /// it into the switch below once its script accepts the flag, and add a case
    /// to `--probe-review-rules`):
    ///  - `spotlight`: `spotlight-audit.sh` fences every unfenced folder under its
    ///    roots; one folder at a time is done by the app writing the marker file.
    ///  - `tmReclaim`: `tm-reclaim.sh` thins snapshots; there are no rows to list.
    public var approvalFlag: String? {
        switch self {
        case .memoryClean, .reclaim: "--only-pids"
        case .storageClean, .janitor, .tempClean, .loginItems, .unusedApps, .recordings: "--only-paths"
        case .spotlight, .tmReclaim: nil
        case .networkSnapshot, .memoryReport, .storageReport, .installAgents, .uninstallAgents,
             .sudoersInstall, .eject: nil     // not cleaners: no apply
        }
    }

    /// Whether the kind's script takes the reviewed list (`--only-pids` or
    /// `--only-paths`). Those apply only what is in it. The others cannot:
    /// Spotlight's audit fences every unfenced folder under its roots, and
    /// `tm-reclaim.sh` has no list flag, so for them the reviewed preview is
    /// the only gate.
    public var takesReviewedList: Bool { approvalFlag != nil }

    // MARK: - arguments

    private func modeArgs(_ options: JobOptions) -> [String] {
        switch self {
        case .storageClean: options.deep ? ["--mode", "deep", "--prune-snapshots"] : []
        case .tempClean: options.permanent ? ["--permanent"] : []
        case .memoryClean: options.includeBusyOrphans ? ["--orphans-all"] : []
        case .reclaim: options.alsoQuit.isEmpty ? [] : ["--apps-list", options.alsoQuit.joined(separator: "\n")]
        default: []
        }
    }

    /// Arguments for a preview. Never carries an action flag.
    public func previewArgs(_ options: JobOptions) throws -> [String] {
        guard isCleaner else { throw JobKindError.unsupported(self, .preview) }
        switch self {
        case .memoryClean, .reclaim, .storageClean, .janitor, .tempClean:
            return ["--dry-run"] + modeArgs(options)
        case .spotlight, .loginItems, .tmReclaim:
            return ["--dry-run"]
        case .unusedApps:
            return ["--stale-apps"]
        case .recordings:
            return ["--recordings-older-than", String(options.recordingsDays)]
        default:
            throw JobKindError.unsupported(self, .preview)
        }
    }

    /// Arguments for an apply. `approvedFile` is what `ApprovedSet.writeFile`
    /// returned. Internal on purpose: the only caller is `JobStore`, which
    /// only builds one from a finished preview.
    func applyArgs(_ options: JobOptions, approvedFile: URL?) throws -> [String] {
        let approval = approvalFlag.flatMap { flag in approvedFile.map { [flag, $0.path] } } ?? []
        switch self {
        case .memoryClean, .reclaim, .storageClean, .janitor, .tempClean:
            return ["--apply"] + modeArgs(options) + approval
        case .loginItems:
            return ["--apply"] + approval
        case .spotlight:
            return ["--apply"]
        case .tmReclaim:
            // tm-reclaim.sh acts without a flag today (its dry run is
            // `--dry-run`); when it gains `--apply` this is the one line to change.
            return []
        case .unusedApps:
            return ["--stale-apps", "--execute", "--yes"] + approval
        case .recordings:
            return ["--recordings-older-than", String(options.recordingsDays), "--execute", "--yes"] + approval
        default:
            throw JobKindError.unsupported(self, .apply)
        }
    }

    /// Arguments for a read-only or one-shot run.
    func runArgs(_ options: JobOptions) throws -> [String] {
        switch self {
        case .networkSnapshot, .memoryReport, .storageReport: return []
        case .installAgents: return ["install"]
        case .uninstallAgents: return ["uninstall"]
        case .sudoersInstall: return ["sudoers-install"]
        case .eject:
            guard let mount = options.mountPoint, !mount.isEmpty else {
                throw JobKindError.missingOption("mountPoint")
            }
            return ["--eject", mount]
        default:
            // A cleaner only runs by hand as its scheduled run.
            guard isCleaner, let replay = options.scheduleArguments else {
                throw JobKindError.unsupported(self, .run)
            }
            return replay
        }
    }

    /// The commands a job starts, in order.
    func commands(intent: JobIntent, options: JobOptions, approvedFile: URL?) throws -> [EngineCommand] {
        let args: [String]
        switch intent {
        case .preview: args = try previewArgs(options)
        case .apply: args = try applyArgs(options, approvedFile: approvedFile)
        case .run: args = try runArgs(options)
        }
        return scripts.map { EngineCommand(script: $0, args: args) }
    }
}
