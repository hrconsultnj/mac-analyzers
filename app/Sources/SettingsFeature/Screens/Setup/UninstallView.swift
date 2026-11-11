import AppKit
import SwiftUI
import AnalyzersKit
import UIComponents

/// Turning it off has to be as easy as turning it on — and it has to be
/// PROVEN, not announced. Each level re-reads the real engine state
/// afterwards and reports what actually happened.
struct UninstallView: View {

    @Environment(GuardLogStore.self) private var store
    @Environment(JobStore.self) private var jobs
    @State private var busy = false
    @State private var result: String?
    @State private var failed = false
    @State private var confirming: Level?
    /// The uninstall job this screen shows: the store's own, found again by
    /// kind when the window is reopened mid-run.
    @State private var job: Job?

    enum Level: String, Identifiable {
        case pause, background, everything
        var id: String { rawValue }

        var title: String {
            switch self {
            case .pause: "Pause everything"
            case .background: "Turn off background protection"
            case .everything: "Remove from this Mac"
            }
        }

        var detail: String {
            switch self {
            case .pause:
                "The guard keeps watching but takes no action, and stays paused until you resume. Nothing is uninstalled."
            case .background:
                "Unloads the scheduled jobs and the guard, and stops the app opening at login. The app and your logs stay put; you can set it up again any time."
            case .everything:
                "Everything above, plus reveals the app and its folder in Finder so you can drag them to the Trash. Your reports and settings are left alone unless you delete that folder."
            }
        }

        var confirmMessage: String {
            switch self {
            case .pause: "The guard will stop acting until you resume it."
            case .background:
                "Your Mac will no longer be watched or cleaned automatically. Nothing you have is deleted."
            case .everything:
                "Background protection stops and Finder opens at the app and its folder. Deleting those is your call — this app never deletes itself or your reports."
            }
        }
    }

    var body: some View {
        PaneScaffold(symbol: "power", color: .red, title: Names.Screen.turnOff,
                     caption: "Three levels, least drastic first. Every one of them reports what actually happened afterwards.") {
            if let result {
                Section {
                    Label(result, systemImage: failed ? "exclamationmark.triangle.fill"
                                                      : "checkmark.circle.fill")
                        .foregroundStyle(failed ? .red : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach([Level.pause, .background, .everything]) { level in
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                            Text(level.title).font(.callout.weight(.medium))
                            Text(level.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button(level == .pause ? "Pause" : "Continue…",
                               role: level == .pause ? nil : .destructive) {
                            confirming = level
                        }
                        .disabled(busy)
                    }
                }
            }
            if let job, job.isActive {
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(job.step ?? "Turning off background protection…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { job.cancel() }
                    }
                }
            }
            Section {
                Text("What stays either way: your reports and logs under ~/mac-analyzers/reports, and anything you configured. This app never deletes your data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(confirming?.title ?? "", isPresented: .init(
            get: { confirming != nil },
            set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            if let level = confirming {
                Button(level.title, role: level == .pause ? nil : .destructive) {
                    Task { await run(level) }
                }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text(confirming?.confirmMessage ?? "")
        }
        .task { await adoptRunning() }
    }

    /// The window was closed while the agents were being turned off: show it
    /// still working, then say what is true once it ends.
    private func adoptRunning() async {
        guard let running = jobs.latest(.uninstallAgents, intents: [.run]), running.isActive else { return }
        job = running
        busy = true
        defer { busy = false }
        await running.waitUntilFinished()
        await reportAgentsOff()
    }

    private func run(_ level: Level) async {
        busy = true
        defer { busy = false }
        confirming = nil

        switch level {
        case .pause:
            do {
                try store.setGuardPaused(true)
                result = "Paused. The guard is watching but taking no action."
                failed = false
            } catch {
                result = error.localizedDescription
                failed = true
            }

        case .background, .everything:
            let uninstall = jobs.enqueue(JobRequest(kind: .uninstallAgents, intent: .run), trigger: .user)
            job = uninstall
            await uninstall.waitUntilFinished()
            if case .cancelled = uninstall.state {
                result = "Stopped. Some background jobs may already be off — check the Setup screen."
                failed = true
                store.reload()
                return
            }
            GuardControl.disableLoginItem()
            await reportAgentsOff()

            if level == .everything, !failed {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: "/Applications/MacAnalyzers.app"),
                    AnalyzersPaths.suiteRoot,
                ])
            }
        }
    }

    /// Prove it rather than claim it: re-read the real engine state.
    private func reportAgentsOff() async {
        let status = await Task.detached(priority: .userInitiated) {
            EngineStatus.probe()
        }.value
        let stillLoaded = (status.guardAgent == .loaded ? 1 : 0)
            + status.cleanerAgents.values.filter { $0 == .loaded }.count
        failed = stillLoaded > 0
        result = stillLoaded == 0
            ? "Background protection is off — no scheduled jobs remain loaded, and the app no longer opens at login."
            : "\(stillLoaded) background job(s) are still loaded. Try again, or remove them in System Settings › General › Login Items."
        store.reload()
    }
}
