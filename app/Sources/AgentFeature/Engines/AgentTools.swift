import Foundation
import AnalyzersKit

/// The capability-gated tool registry: everything the agent can DO on this
/// Mac, and nothing else. Every entry checks the enabled capability set
/// BEFORE it runs; a gated call returns a refusal STRING the model reads —
/// never a silent kill — so the agent can explain itself and the person can
/// see why nothing happened.
///
/// Execution paths are exactly the app's own:
///  - read-only scans shell the existing analyzers as tracked jobs
///    (`JobStore.enqueue`), so Activity lists every one and the toolbar shows
///    it running;
///  - a cleanup proposal is a normal PREVIEW job (dry run);
///  - `runApprovedCleanup` is the ONLY apply path and goes through
///    `JobStore.apply(from:approved:)` — a cleaner script is never invoked
///    directly. The approved set can only shrink: the actions come from the
///    permission round-trip (what the user ticked on the preview screen), the
///    kernel refuses a stale or dismissed preview, and the engine script
///    intersects the list with its own findings at apply time, so a key that
///    no longer exists (or was never in the preview) is skipped, never added.
///
/// The allowlist/protect-list invariants are inherited from the scripts
/// themselves — this registry never reimplements them and never touches
/// `lib/approved-list.sh`, `lib/live-sessions.sh` or `lib/coding-agents.tsv`.
public struct AgentTools: Sendable {

    /// The one store the app owns; scans and applies queue on its single
    /// engine lane like every other run.
    public let jobStore: JobStore

    public init(jobStore: JobStore) {
        self.jobStore = jobStore
    }

    /// How many characters of a saved report the model reads in one call —
    /// context discipline is the RAM control on-device and the cost control
    /// everywhere else; the person reads the full report in the app.
    static let reportExcerptLimit = 4_000

    // MARK: - the catalog

    public enum Tool: String, CaseIterable, Sendable {
        case scanStorage
        case scanMemory
        case scanNetwork
        case readReport
        case proposeCleanup
        case runApprovedCleanup
        case suggestRule

        /// The capability that must be enabled for this tool to run
        /// (`AgentCapability.id`).
        var requiredCapability: String {
            switch self {
            case .scanStorage, .scanMemory, .scanNetwork: "runScans"
            case .readReport: "readReports"
            case .proposeCleanup: "proposeCleanups"
            case .runApprovedCleanup: "startApprovedCleans"
            case .suggestRule: "suggestRules"
            }
        }

        var title: String {
            switch self {
            case .scanStorage: "scanStorage"
            case .scanMemory: "scanMemory"
            case .scanNetwork: "scanNetwork"
            case .readReport: "readReport"
            case .proposeCleanup: "proposeCleanup"
            case .runApprovedCleanup: "runApprovedCleanup"
            case .suggestRule: "suggestRule"
            }
        }

        /// One line the system prompt carries, so the model knows what exists
        /// and what each call takes.
        var declaration: String {
            switch self {
            case .scanStorage:
                "scanStorage — run the read-only storage analyzer now (a tracked scan; nothing is changed). {}"
            case .scanMemory:
                "scanMemory — run the read-only memory analyzer now (a tracked scan; nothing is changed). {}"
            case .scanNetwork:
                "scanNetwork — take the read-only network snapshot (a tracked scan; nothing is changed). {}"
            case .readReport:
                #"readReport — read the newest saved scan report. {"kind": "storage" | "memory"}"#
            case .proposeCleanup:
                #"proposeCleanup — run a cleanup tool as a PREVIEW (dry run; nothing is deleted). {"kind": "janitor" | "tempClean" | "storageClean" | "memoryClean" | "recordings" | "unusedApps"}. Show the result to the person; nothing is applied from a preview alone."#
            case .runApprovedCleanup:
                #"runApprovedCleanup — apply a cleanup the person has approved on the preview screen. {"preview": "<preview job id>", "actions": ["<approved action>", …]}. Only what the person ticked is ever applied. This is the only tool that can change files."#
            case .suggestRule:
                #"suggestRule — suggest a setting change in words for the person to decide on. {"rule": "<the suggestion>"}. Settings are never changed by the agent."#
            }
        }
    }

    /// The tool declarations for the enabled set, as system-prompt lines.
    /// Disabled tools are not named at all: the model should not reach for
    /// something it may not use, and the registry still refuses it if it tries.
    public func declarations(enabled: Set<String>) -> String {
        Tool.allCases
            .filter { enabled.contains($0.requiredCapability) }
            .map { "- \($0.declaration)" }
            .joined(separator: "\n")
    }

    /// Runs one tool call and returns the text the model reads as its result.
    /// Every branch — refusal, failure, success — is a sentence, because the
    /// model can only answer with what it is told.
    public func run(_ tool: Tool, arguments: JSON, capabilities: Set<String>) async -> String {
        guard capabilities.contains(tool.requiredCapability) else {
            return Self.refusal(for: tool)
        }
        let fields = arguments.stringFields
        switch tool {
        case .scanStorage:
            return await runScan(.storageReport)
        case .scanMemory:
            return await runScan(.memoryReport)
        case .scanNetwork:
            return await runScan(.networkSnapshot)
        case .readReport:
            return await readReport(kind: fields["kind"] ?? "storage")
        case .proposeCleanup:
            return await proposeCleanup(kind: fields["kind"] ?? "")
        case .runApprovedCleanup:
            return await runApprovedCleanup(arguments: arguments)
        case .suggestRule:
            return suggestRule(fields["rule"] ?? "")
        }
    }

    /// Why a gated tool did not run — words the model passes on to the person.
    public static func refusal(for tool: Tool) -> String {
        let screen = "Settings › Agents › Capabilities"
        switch tool {
        case .scanStorage, .scanMemory, .scanNetwork:
            return "Refused: the 'Run scans' capability is switched off (\(screen)), so no scan was run. Answer from the reports that already exist, or tell the person they can switch scans on there."
        case .readReport:
            return "Refused: the 'Read my reports' capability is switched off (\(screen)), so no report was read. Tell the person they can switch it on there."
        case .proposeCleanup:
            return "Refused: the 'Propose cleanups' capability is switched off (\(screen)), so no preview was made. Tell the person they can switch it on there."
        case .runApprovedCleanup:
            return "Refused: the 'Clean what I approved' capability is switched off (\(screen)), so nothing was applied. Nothing has been changed. Tell the person they can switch it on there."
        case .suggestRule:
            return "Refused: the 'Suggest better rules' capability is switched off (\(screen)). Tell the person they can switch it on there."
        }
    }

    // MARK: - scans (read-only)

    @MainActor
    private func runScan(_ kind: JobKind) async -> String {
        let job = jobStore.enqueue(JobRequest(kind: kind, intent: .run), trigger: .user)
        return await waitFor(job, what: kind.rawValue)
    }

    // MARK: - readReport (reads saved reports, never a process)

    /// The newest saved report of `kind`, as an excerpt. This is file reading,
    /// not a process — the analyzers already wrote these.
    @MainActor
    private func readReport(kind: String) -> String {
        let roots: [String: URL] = ["storage": AnalyzersPaths.storageReports,
                                    "memory": AnalyzersPaths.memoryReports]
        guard let root = roots[kind.lowercased()] else {
            return "There is no report of that kind. kind is \"storage\" or \"memory\"."
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "md" } ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let newest = files.max(by: { modified($0) < modified($1) }) else {
            return "No \(kind) report has been written yet. Call \(kind == "memory" ? "scanMemory" : "scanStorage") first, then read the report it wrote."
        }
        let text = (try? String(contentsOf: newest, encoding: .utf8)) ?? ""
        guard !text.isEmpty else { return "The newest \(kind) report is empty." }
        // Context discipline: the model reads an excerpt, and names the file
        // so the person can open the whole report themselves.
        let excerpt = String(text.prefix(Self.reportExcerptLimit))
        return "Newest \(kind) report (\(AnalyzersPaths.displayPath(newest))):\n\n\(excerpt)\n\n(excerpt; the full report is on this Mac.)"
    }

    // MARK: - proposeCleanup (preview only)

    /// The cleaners an agent may preview. The whole reviewed set is offered,
    /// because a preview is a dry run — the gate that matters is the apply.
    private static let previewableKinds: [String: JobKind] = [
        "janitor": .janitor, "tempClean": .tempClean, "storageClean": .storageClean,
        "memoryClean": .memoryClean, "recordings": .recordings, "unusedApps": .unusedApps,
    ]

    @MainActor
    private func proposeCleanup(kind: String) async -> String {
        guard let jobKind = Self.previewableKinds[kind] else {
            return "Unknown cleanup kind \"\(kind)\". One of: \(Self.previewableKinds.keys.sorted().joined(separator: ", ")). Nothing was run."
        }
        let job = jobStore.enqueue(JobRequest(kind: jobKind, intent: .preview), trigger: .user)
        let result = await waitFor(job, what: "\(kind) preview")
        // The preview id is what the permission round-trip carries, so the
        // apply names exactly this reviewed run and nothing newer.
        return result + "\nPreview job id: \(job.id.uuidString). Tell the person what this would do; only a preview was run, nothing has been changed."
    }

    // MARK: - runApprovedCleanup (the only apply)

    /// Applies a previewed cleanup through the kernel. `arguments` carries
    /// `preview` (the preview job id) and `actions` (the approved action
    /// strings, already narrowed by the permission round-trip — the session
    /// layer refuses a set wider than what was proposed). For kinds whose
    /// engine takes a reviewed list, the actions ARE that list; for kinds that
    /// take none, the reviewed preview itself is the gate.
    @MainActor
    private func runApprovedCleanup(arguments: JSON) async -> String {
        guard case .object(let object) = arguments,
              let previewRaw = object["preview"]?.stringValue,
              let previewID = UUID(uuidString: previewRaw)
        else {
            return "Refused: an apply needs the preview job id (\"preview\"). Nothing was applied."
        }
        guard let preview = jobStore.jobs.first(where: {
            $0.id == previewID && $0.intent == .preview && $0.kind.isCleaner
        }) else {
            return "Refused: no cleanup preview with that id was found. Nothing was applied — preview first with proposeCleanup."
        }
        let actions = (object["actions"] ?? .array([])).listOfStrings
        let approved: ApprovedSet = preview.kind.takesReviewedList
            ? ApprovedSet(approvable: actions, deselected: [])
            : .everything
        let applyJob = jobStore.apply(from: preview, approved: approved)
        if case .failed(let failure) = applyJob.state {
            return "The apply was refused before it started: \(failure.message) Nothing has been changed."
        }
        let result = await waitFor(applyJob, what: "\(applyJob.kind.rawValue) apply")
        return result + "\nApply job id: \(applyJob.id.uuidString). The person can undo or inspect it in Activity."
    }

    // MARK: - suggestRule (words only)

    /// Suggestions are never applied: settings belong to the person. The
    /// result is the proposal, framed for the person to decide on.
    private func suggestRule(_ rule: String) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "An empty suggestion was not recorded. Give the suggestion in \"rule\"." }
        return "Suggestion to show the person (nothing has been changed — settings are always theirs to make): \(trimmed)"
    }

    // MARK: - waiting on the single engine lane

    /// Waits for `job` to leave the lane (or times out and stops it), then
    /// returns the short summary the model reads. Scans and previews can take
    /// minutes; the agent turn simply waits, because the person is watching
    /// the same run in the toolbar.
    @MainActor
    private func waitFor(_ job: Job, what: String,
                         timeout: Duration = .seconds(15 * 60)) async -> String {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !job.state.isFinished {
            guard ContinuousClock.now < deadline else {
                job.cancel()
                return "The \(what) took more than 15 minutes and was stopped. Nothing was changed."
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        var text = "Ran the \(what) as a tracked job (in Activity: \(job.id.uuidString.prefix(8)))."
        switch job.state {
        case .succeeded(let outcome):
            text += " It finished."
            if let note = outcome.note { text += " \(note)" }
            if !job.tailLines.isEmpty {
                text += "\nWhat it reported:\n" + job.tailLines.joined(separator: "\n")
            }
        case .failed(let failure):
            text += " It failed: \(failure.message)"
        case .cancelled:
            text += " It was stopped. Nothing was changed."
        default:
            break
        }
        return text
    }
}

private extension Job {
    /// The run's own last lines, cleaned of engine noise (`###` group
    /// markers, banners already shown elsewhere), capped for context
    /// discipline — the model gets the gist, the person gets the full log in
    /// the job screen.
    var tailLines: [String] {
        let noise: (String) -> Bool = { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("#")
        }
        let kept = Array(lines.reversed().filter { !noise($0) }.prefix(8)).reversed()
        return kept.map { String($0.prefix(200)) }
    }
}

extension JSON {
    /// The array's string elements, in order. Non-string elements are dropped:
    /// an approved action is a string by contract.
    var listOfStrings: [String] {
        guard case .array(let items) = self else { return [] }
        return items.compactMap(\.stringValue)
    }
}
