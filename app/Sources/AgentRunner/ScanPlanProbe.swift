import Foundation
@_spi(TestSupport) import AnalyzersKit

// `agent-runner --probe-scan-plan` judges itself (exit 1 when a rule breaks): what Overview's Scan Everything queues is
// only reports and previews, in the right order, each one the store accepts, with Old Recordings left out when no source
// is on; and the store's batch refuses a second batch while one is going and can cancel the part that has not started.
// The batch part runs a stand-in script that only sleeps, with its own job index in a scratch folder: no real engine
// script runs, and nothing is applied.

@MainActor func probeScanPlan() async -> Never {
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : ": " + detail))
        if !ok { failures += 1 }
    }
    RecordingSourceCatalog.useList(at: ProbeSandbox.sourceRoot.appending(path: "lib/recording-sources.tsv"))

    var storage = StorageTunables()
    storage.recordingSourcesConfigured = true
    storage.recordingSources = [RecordingSourceEntry(id: RecordingSource.customID, enabled: true, path: "/Users/someone/Recordings")]
    storage.recordingsDays = 180
    let plan = ScanPlan.requests(storage: storage)
    let kinds = plan.map(\.kind)
    print("plan: " + kinds.map(\.rawValue).joined(separator: ", "))

    check("13 scans when a recording source is on", plan.count == 13, "\(plan.count)")
    check("each scan is queued once", Set(kinds).count == kinds.count)
    check("only previews and reports", plan.allSatisfy { $0.intent == .preview || $0.intent == .run })
    check("no apply", !plan.contains { $0.intent == .apply })
    check("none carries an approved list", plan.allSatisfy { $0.approved == nil })
    let refused = plan.compactMap { request in JobStore.refusal(for: request, trigger: .user).map { "\(request.kind.rawValue): \($0)" } }
    check("the store refuses none of them", refused.isEmpty, refused.joined(separator: "; "))
    let never: Set<JobKind> = [.installAgents, .uninstallAgents, .sudoersInstall, .eject]
    check("no installer, sudoers rule or eject", Set(kinds).isDisjoint(with: never))
    check("reports run, cleaners preview", plan.allSatisfy { $0.kind.isCleaner == ($0.intent == .preview) })
    check("the three reports come first", Set(kinds.prefix(3)) == [.storageReport, .memoryReport, .networkSnapshot], "\(kinds.prefix(3))")
    check("memory cleanup and reclaim are last", Array(kinds.suffix(2)) == [.memoryClean, .reclaim], "\(kinds.suffix(2))")
    let others = plan.filter { $0.kind != .recordings }
    check("every preview but Old Recordings uses its screen's own default options", others.allSatisfy { $0.options == JobOptions() })
    check("Old Recordings uses the saved days", plan.first { $0.kind == .recordings }?.options == JobOptions(recordingsDays: 180))

    // no source on: the three ways the Old Recordings screen says so
    var none = storage
    none.recordingSources = [RecordingSourceEntry(id: RecordingSource.customID, enabled: false, path: "/Users/someone/Recordings")]
    check("recordings skipped when every source is off", !ScanPlan.requests(storage: none).contains { $0.kind == .recordings })
    none.recordingSources = []
    check("recordings skipped when the saved list is empty", !ScanPlan.requests(storage: none).contains { $0.kind == .recordings })
    check("12 scans without it", ScanPlan.requests(storage: none).count == 12)
    check("recordings skipped on a fresh install", !ScanPlan.requests(storage: StorageTunables()).contains { $0.kind == .recordings })
    var legacy = StorageTunables()
    legacy.recordingsDir = "/Users/someone/Recordings"
    check("the one folder an older install set still counts", ScanPlan.requests(storage: legacy).contains { $0.kind == .recordings })

    // the batch: stand-in script that sleeps
    let dir = ProbeScratch.folder("ma-probe-scan-plan")
    let sleeper = dir.appending(path: "sleep.sh")
    try? "#!/bin/bash\nsleep 30\n".write(to: sleeper, atomically: true, encoding: .utf8)
    chmod(sleeper.path, 0o755)
    let store = JobStore(ledger: JobLedger(url: dir.appending(path: "jobs.jsonl")))
    store.scriptOverride = sleeper
    let started = store.enqueueBatch(Array(plan.prefix(3)), trigger: .user)
    check("a batch is queued", started.count == 3 && store.batchIsActive, "\(started.count) jobs")
    check("a second batch is not queued while the first is going", store.enqueueBatch(plan, trigger: .user).isEmpty && store.batch.count == 3)
    store.cancelRestOfBatch()
    check("Cancel the Rest stops what has not started", started.dropFirst().allSatisfy { if case .cancelled = $0.state { true } else { false } })
    check("and leaves the running one to finish", !started[0].state.isFinished)
    started[0].cancel()
    for _ in 0..<100 where store.batchIsActive { try? await Task.sleep(for: .milliseconds(50)) }
    check("the batch ends when the running one is stopped", !store.batchIsActive)
    check("a new batch can then be queued", !store.enqueueBatch(Array(plan.prefix(1)), trigger: .user).isEmpty)
    store.cancelRestOfBatch()
    store.batch.first?.cancel()
    _ = await store.stopEverything()

    print(failures == 0 ? "\nscan plan holds" : "\n\(failures) check(s) failed")
    ProbeScratch.finish(failures == 0 ? 0 : 1)
}
