import AnalyzersKit
import Foundation
import Observation

/// The reports on disk, the one being read, and the jobs that write new ones.
@MainActor @Observable
final class ReportsModel {

    private(set) var reports: [ReportDocument] = []
    private(set) var loaded = false
    /// The rendered report on the right, and which report it is.
    private(set) var preface: [MarkdownBlock] = []
    private(set) var sections: [ReportSection] = []
    private(set) var blocksFor: ReportDocument.ID?
    var selection: ReportDocument.ID? {
        didSet { if selection != oldValue { Task { await loadBlocks() } } }
    }
    /// Each kind's job: the store's own, found again by kind when the window is
    /// reopened mid-run.
    private(set) var jobs: [ReportDocument.Kind: Job] = [:]

    func reports(of kind: ReportDocument.Kind) -> [ReportDocument] { reports.filter { $0.kind == kind } }

    var selected: ReportDocument? { reports.first { $0.id == selection } }

    /// The kind being written, if any.
    var writing: ReportDocument.Kind? {
        ReportDocument.Kind.allCases.first { jobs[$0]?.isActive ?? false }
    }

    var failure: String? { ReportDocument.Kind.allCases.lazy.compactMap { self.jobs[$0]?.failureMessage }.first }

    /// One stamp per kind, so the screen can tell when a job moved on.
    var stamps: [JobStamp] { ReportDocument.Kind.allCases.map { JobStamp(jobs[$0]) } }

    func adopt(from store: JobStore) {
        for kind in ReportDocument.Kind.allCases { jobs[kind] = store.latest(kind.jobKind, intents: [.run]) }
    }

    func write(_ kind: ReportDocument.Kind, in store: JobStore) {
        jobs[kind] = store.enqueue(JobRequest(kind: kind.jobKind, intent: .run), trigger: .user)
    }

    func stop() { jobs.values.forEach { $0.cancel() } }

    func reload(selectNewestOf kind: ReportDocument.Kind? = nil) async {
        reports = await Task.detached(priority: .userInitiated) { ReportLibrary.all() }.value
        loaded = true
        if let kind, let newest = reports.first(where: { $0.kind == kind }) {
            selection = newest.id
        } else if selection == nil || selected == nil {
            selection = reports.first?.id
        }
    }

    private func loadBlocks() async {
        guard let report = selected else { preface = []; sections = []; blocksFor = nil; return }
        let url = report.url
        let parsed = await Task.detached(priority: .userInitiated) {
            ReportSection.split((try? String(contentsOf: url, encoding: .utf8)).map(ReportMarkdown.blocks(from:)) ?? [])
        }.value
        guard selection == report.id else { return }
        preface = parsed.preface
        sections = parsed.sections
        blocksFor = report.id
    }
}
